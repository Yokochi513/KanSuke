import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/app.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/auth/data/auth_repository.dart';
import 'package:kansuke/features/invites/application/invite_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // KanSukeApp が表示テーマの設定を読むため、メモリ上のモックを差し込む。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('未ログインならサインイン画面を表示しGoogle認証後はカレンダーへ切り替わる', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();

    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('Googleで続行'), findsOneWidget);

    await tester.tap(find.text('Googleで続行'));
    await tester.pumpAndSettle();

    expect(repository.googleSignInCount, 1);
    // FR-8: アカウント作成時に自動生成された個人カレンダーが、カレンダー切替
    // タイトルの既定表示になる。
    expect(find.text(_personalCalendarName), findsOneWidget);
    expect(find.text('サインイン'), findsNothing);
  });

  testWidgets('iOSではApple認証ボタンを表示して認証できる', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      await _testApp(repository, appleSignInAvailable: true),
    );
    await tester.pump();

    await tester.tap(find.text('Appleでサインイン'));
    await tester.pumpAndSettle();

    expect(repository.appleSignInCount, 1);
    expect(find.text(_personalCalendarName), findsOneWidget);
  });

  testWidgets('アカウント初期化に失敗したユーザーには再試行を促すエラーを表示する', (tester) async {
    final repository = FakeAuthRepository(
      signInError: const AuthSetupFailedException(),
    );
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();

    await tester.tap(find.text('Googleで続行'));
    await tester.pumpAndSettle();

    expect(find.text('アカウントの初期化に失敗しました。時間をおいて、もう一度お試しください。'), findsOneWidget);
    expect(find.text('サインイン'), findsOneWidget);
  });

  testWidgets('サインアウトするとサインイン画面へ戻る', (tester) async {
    // FR-8: 設定画面にカレンダーセクションが増え、既定のテスト表示領域では
    // 末尾の要素が描画範囲外になる。ensureVisible が要素を見つけられるよう
    // 表示領域を広げる。
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeAuthRepository(initiallySignedIn: true);
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('サインアウト'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('サインアウト'));
    await tester.pumpAndSettle();

    expect(repository.signOutCount, 1);
    expect(find.text('サインイン'), findsOneWidget);
  });

  testWidgets('ログイン済みならカレンダー画面と各プレースホルダへ遷移できる', (tester) async {
    final repository = FakeAuthRepository(initiallySignedIn: true);
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();

    expect(find.text('カレンダー'), findsOneWidget);

    // カレンダーで選択済みの日付を再タップすると日別一覧へ遷移する（予定なしなので空状態）。
    final today = find.text('${DateTime.now().day}').first;
    await tester.tap(today);
    await tester.pump();
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(find.text('予定はありません'), findsOneWidget);
  });

  testWidgets('予定作成の日付ピッカーが日本語表記になる（Issue #58）', (tester) async {
    final repository = FakeAuthRepository(initiallySignedIn: true);
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();

    final today = find.text('${DateTime.now().day}').first;
    await tester.tap(today);
    await tester.pump();
    await tester.tap(today);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, '開始日'));
    await tester.pumpAndSettle();

    // 曜日ヘッダが日本語（例:「月」）で描画され、英語表記（S/M/T...）にならないこと。
    expect(find.text('月'), findsWidgets);
  });
}

/// アカウント作成時に Auth Blocking Function が生成する個人カレンダーの名前。
const _personalCalendarName = 'ファミリーのカレンダー';

Future<Widget> _testApp(
  AuthRepository repository, {
  bool appleSignInAvailable = false,
}) async {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      appleSignInAvailableProvider.overrideWithValue(appleSignInAvailable),
      // カレンダーが購読する Firestore はテスト用の fake に差し替える。
      firestoreProvider.overrideWithValue(await _signedUpFirestore()),
      // FR-9: 招待リンクの受け口（Issue #90）はプラットフォームのプラグインを
      // 使うため、テストではリンクが来ない空のストリームにする。
      inviteLinkStreamProvider.overrideWith((ref) => const Stream<Uri>.empty()),
    ],
    child: const KanSukeApp(),
  );
}

/// FR-8: 個人カレンダーはアカウント作成時に Auth Blocking Function が生成するため、
/// テストでは生成済みの状態（自分だけが参加するカレンダー）を用意する。
Future<FakeFirebaseFirestore> _signedUpFirestore() async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 7, 1));
  await firestore.collection('calendars').doc('personal').set({
    'name': _personalCalendarName,
    'memberIds': ['family-user'],
    'creatorId': 'family-user',
    'createdAt': now,
    'updatedAt': now,
  });
  return firestore;
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({bool initiallySignedIn = false, this.signInError})
    : _session = initiallySignedIn
          ? const AuthSession(uid: 'family-user')
          : null;

  final AuthException? signInError;
  final _controller = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;

  int googleSignInCount = 0;
  int appleSignInCount = 0;
  int signOutCount = 0;

  @override
  Stream<AuthSession?> authStateChanges() async* {
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCount++;
    await _signIn();
  }

  @override
  Future<void> signInWithApple() async {
    appleSignInCount++;
    await _signIn();
  }

  @override
  Future<void> initializeGoogleSignIn() async {}

  @override
  Stream<AuthException?> get googleWebSignInResults =>
      const Stream<AuthException?>.empty();

  Future<void> _signIn() async {
    if (signInError case final error?) {
      throw error;
    }
    _session = const AuthSession(uid: 'family-user');
    _controller.add(_session);
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _session = null;
    _controller.add(null);
  }
}

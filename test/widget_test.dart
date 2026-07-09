import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/app.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/auth/data/auth_repository.dart';
import 'package:kansuke/features/notifications/application/notification_providers.dart';

void main() {
  testWidgets('未ログインならサインイン画面を表示しGoogle認証後はカレンダーへ切り替わる', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(_testApp(repository));
    await tester.pump();

    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('Googleで続行'), findsOneWidget);

    await tester.tap(find.text('Googleで続行'));
    await tester.pumpAndSettle();

    expect(repository.googleSignInCount, 1);
    // FR-8: 初回サインイン後、既定カレンダー（わが家）の自動生成が完了し
    // カレンダー切替タイトルにその名前が表示される。
    expect(find.text('わが家'), findsOneWidget);
    expect(find.text('サインイン'), findsNothing);
  });

  testWidgets('iOSではApple認証ボタンを表示して認証できる', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(_testApp(repository, appleSignInAvailable: true));
    await tester.pump();

    await tester.tap(find.text('Appleでサインイン'));
    await tester.pumpAndSettle();

    expect(repository.appleSignInCount, 1);
    expect(find.text('わが家'), findsOneWidget);
  });

  testWidgets('allowlist外ユーザーには利用権限エラーを表示する', (tester) async {
    final repository = FakeAuthRepository(
      signInError: const AuthAccessDeniedException(),
    );
    await tester.pumpWidget(_testApp(repository));
    await tester.pump();

    await tester.tap(find.text('Googleで続行'));
    await tester.pumpAndSettle();

    expect(find.text('利用権限がありません'), findsOneWidget);
    expect(find.text('サインイン'), findsOneWidget);
  });

  testWidgets('サインアウトするとサインイン画面へ戻る', (tester) async {
    // FR-8: 設定画面にカレンダーセクションが増え、既定のテスト表示領域では
    // 末尾の要素が描画範囲外になる。ensureVisible が要素を見つけられるよう
    // 表示領域を広げる。
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeAuthRepository(initiallySignedIn: true);
    await tester.pumpWidget(_testApp(repository));
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
    await tester.pumpWidget(_testApp(repository));
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
    await tester.pumpWidget(_testApp(repository));
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

Widget _testApp(
  AuthRepository repository, {
  bool appleSignInAvailable = false,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      appleSignInAvailableProvider.overrideWithValue(appleSignInAvailable),
      // カレンダーが購読する Firestore はテスト用の fake に差し替える。
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      // FR-5: 実 FirebaseMessaging には触れず、通知ブートストラップを無効化する。
      notificationBootstrapProvider.overrideWith((ref) async {}),
      deviceRegistrationServiceProvider.overrideWithValue(
        _NoopDeviceRegistrationService(),
      ),
    ],
    child: const KanSukeApp(),
  );
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

class _NoopDeviceRegistrationService implements DeviceRegistrationService {
  @override
  Future<void> registerCurrentToken(String uid) async {}

  @override
  Future<void> unregisterForSignOut(String uid) async {}
}

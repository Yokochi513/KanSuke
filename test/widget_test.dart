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
import 'package:kansuke/features/notifications/application/notification_providers.dart';
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

  testWidgets('メールログインの入力チェックと認証後のカレンダー遷移', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();
    await tester.tap(find.text('メールアドレスでログイン'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();
    expect(find.text('メールアドレスを入力してください。'), findsOneWidget);
    expect(find.text('パスワードを入力してください。'), findsOneWidget);
    expect(repository.emailSignInCount, 0);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' family@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), ' password ');
    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();
    expect(repository.emailSignInCount, 1);
    expect(repository.lastEmail, 'family@example.com');
    expect(repository.lastPassword, ' password ');
    expect(find.text(_personalCalendarName), findsOneWidget);
  });

  testWidgets('メールログインの認証エラーは入力画面に表示される', (tester) async {
    final repository = FakeAuthRepository(
      signInError: const AuthInvalidCredentialsException(),
    );
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();
    await tester.tap(find.text('メールアドレスでログイン'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'family@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrect');
    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();
    expect(find.text('メールアドレスまたはパスワードが正しくありません。'), findsWidgets);
    expect(find.text('ログイン'), findsOneWidget);
  });

  testWidgets('新規登録は短いパスワードと確認不一致を拒否し登録後はカレンダーへ進む', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();
    await tester.tap(find.text('メールアドレスでログイン'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('アカウントを作成'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' new@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.enterText(find.byType(TextFormField).at(2), 'other');
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(find.text('パスワードは6文字以上で入力してください。'), findsOneWidget);
    expect(find.text('パスワードが一致しません。'), findsOneWidget);
    expect(repository.emailSignUpCount, 0);
    await tester.enterText(find.byType(TextFormField).at(1), ' password ');
    await tester.enterText(find.byType(TextFormField).at(2), ' password ');
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(repository.emailSignUpCount, 1);
    expect(repository.emailSignInCount, 0);
    expect(repository.lastEmail, 'new@example.com');
    expect(repository.lastPassword, ' password ');
    expect(find.text(_personalCalendarName), findsOneWidget);
    expect(find.text('登録する'), findsNothing);
  });

  testWidgets('登録失敗は新規登録画面に表示しログインへの切替でエラーを消す', (tester) async {
    const message = 'このメールアドレスは既に登録されています。ログインしてください。';
    final repository = FakeAuthRepository(
      signInError: const AuthSignUpException(message),
    );
    await tester.pumpWidget(await _testApp(repository));
    await tester.pump();
    await tester.tap(find.text('メールアドレスでログイン'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('アカウントを作成'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.enterText(find.byType(TextFormField).at(2), 'password');
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsWidgets);
    expect(find.text('登録する'), findsOneWidget);
    await tester.ensureVisible(find.text('既にアカウントをお持ちの方はログイン'));
    await tester.tap(find.text('既にアカウントをお持ちの方はログイン'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(find.text('ログイン'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
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
    // FR-8: 設定画面のセクションが増え、既定のテスト表示領域では
    // 末尾の要素が描画範囲外になる。ensureVisible が要素を見つけられるよう
    // 表示領域を広げる。
    await tester.binding.setSurfaceSize(const Size(400, 1700));
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
      // FR-5: 実 FirebaseMessaging には触れず、通知ブートストラップを無効化する。
      notificationBootstrapProvider.overrideWith((ref) async {}),
      deviceRegistrationServiceProvider.overrideWithValue(
        _NoopDeviceRegistrationService(),
      ),
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
  int emailSignInCount = 0;
  int emailSignUpCount = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> signUpWithEmailAndPassword(String email, String password) async {
    emailSignUpCount++;
    lastEmail = email;
    lastPassword = password;
    await _signIn();
  }

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    emailSignInCount++;
    lastEmail = email;
    lastPassword = password;
    await _signIn();
  }

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
  Future<void> reauthenticate() async {}

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/app.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/auth/data/auth_repository.dart';

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
    expect(find.text('カレンダー'), findsOneWidget);
    expect(find.text('サインイン'), findsNothing);
  });

  testWidgets('iOSではApple認証ボタンを表示して認証できる', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(_testApp(repository, appleSignInAvailable: true));
    await tester.pump();

    await tester.tap(find.text('Appleでサインイン'));
    await tester.pumpAndSettle();

    expect(repository.appleSignInCount, 1);
    expect(find.text('カレンダー'), findsOneWidget);
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
    final repository = FakeAuthRepository(initiallySignedIn: true);
    await tester.pumpWidget(_testApp(repository));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
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

    await tester.tap(find.text('日別予定一覧'));
    await tester.pumpAndSettle();
    expect(find.text('選択日の予定を表示します'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('予定を編集'));
    await tester.pumpAndSettle();
    expect(find.text('予定を作成・編集します'), findsOneWidget);
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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/firebase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(),
);

// NFR-4: Firebase Authentication の状態を画面出し分けの唯一の情報源にする。
final authStateProvider = StreamProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final appleSignInAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
);

final authActionControllerProvider =
    NotifierProvider<AuthActionController, AuthActionState>(
      AuthActionController.new,
    );

class AuthActionState {
  const AuthActionState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;
}

class AuthActionController extends Notifier<AuthActionState> {
  @override
  AuthActionState build() => const AuthActionState();

  Future<void> signInWithGoogle() {
    return _run(ref.read(authRepositoryProvider).signInWithGoogle);
  }

  Future<void> signInWithApple() {
    return _run(ref.read(authRepositoryProvider).signInWithApple);
  }

  Future<void> signOut() {
    return _run(ref.read(authRepositoryProvider).signOut);
  }

  void clearError() {
    state = const AuthActionState();
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AuthActionState(isLoading: true);
    try {
      await action();
      state = const AuthActionState();
    } on AuthCancelledException {
      state = const AuthActionState();
    } on AuthAccessDeniedException {
      state = const AuthActionState(errorMessage: '利用権限がありません');
    } on AuthException {
      state = const AuthActionState(
        errorMessage: 'サインインに失敗しました。通信環境を確認して、もう一度お試しください。',
      );
    } on Object {
      state = const AuthActionState(
        errorMessage: 'サインインに失敗しました。しばらくしてから、もう一度お試しください。',
      );
    }
  }
}

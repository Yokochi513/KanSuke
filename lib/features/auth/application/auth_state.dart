import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger.dart';
import '../../notifications/application/notification_providers.dart';
import '../data/auth_repository.dart';
import '../data/firebase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = FirebaseAuthRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

// NFR-4: Firebase Authentication の状態を画面出し分けの唯一の情報源にする。
final authStateProvider = StreamProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// サインイン中のユーザー uid。未認証なら null。
///
/// 予定の `updatedBy` 付与など、書き込みの本人特定に用いる。
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).asData?.value?.uid,
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
  StreamSubscription<AuthException?>? _webResultsSubscription;

  @override
  AuthActionState build() {
    ref.onDispose(() => _webResultsSubscription?.cancel());
    return const AuthActionState();
  }

  Future<void> signInWithGoogle() {
    return _run(ref.read(authRepositoryProvider).signInWithGoogle);
  }

  /// Web の GIS ボタン描画前に呼ぶ。Google サインインを初期化し、
  /// ボタン経由で完了するサインイン結果の購読を開始する。
  Future<void> initializeGoogleWebSignIn() {
    final repository = ref.read(authRepositoryProvider);
    _webResultsSubscription ??= repository.googleWebSignInResults.listen(
      _onGoogleWebSignInResult,
    );
    return repository.initializeGoogleSignIn();
  }

  void _onGoogleWebSignInResult(AuthException? error) {
    if (error == null) {
      state = const AuthActionState();
    } else if (error is AuthAccessDeniedException) {
      state = const AuthActionState(errorMessage: '利用権限がありません');
    } else {
      state = const AuthActionState(
        errorMessage: 'サインインに失敗しました。しばらくしてから、もう一度お試しください。',
      );
    }
  }

  Future<void> signInWithApple() {
    return _run(ref.read(authRepositoryProvider).signInWithApple);
  }

  Future<void> signOut() {
    return _run(() async {
      // FR-5: この端末の FCM トークンを devices から外す。Security Rules は
      // auth.uid==uid のみ書込を許可するため、認証セッションが切れる前に行う。
      final uid = ref.read(currentUidProvider);
      if (uid != null) {
        await _unregisterDeviceBestEffort(uid);
      }
      await ref.read(authRepositoryProvider).signOut();
    });
  }

  Future<void> _unregisterDeviceBestEffort(String uid) async {
    try {
      await ref
          .read(deviceRegistrationServiceProvider)
          .unregisterForSignOut(uid);
    } on Object catch (error, stackTrace) {
      // トークン削除に失敗してもサインアウト自体は継続する（ベストエフォート）。
      AppLogger.error(
        'Failed to unregister device token on sign out',
        tag: 'AuthActionController',
        error: error,
        stackTrace: stackTrace,
      );
    }
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

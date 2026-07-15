class AuthSession {
  const AuthSession({required this.uid});

  final String uid;
}

abstract interface class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  /// 現在サインイン中のプロバイダ（Google / Apple）で再認証する（Issue #102）。
  ///
  /// アカウント削除など取り返しのつかない操作の直前に、誤操作・端末の乗っ取りを
  /// 防ぐために求める。キャンセルは [AuthCancelledException]、失敗は
  /// [AuthException]（サインインと同じ体系）で通知する。
  Future<void> reauthenticate();

  Future<void> signOut();

  /// Google サインインの初期化（冪等）。
  ///
  /// Web は authenticate() を持たないため、GIS ボタンを描画する前に
  /// この初期化を完了させ、[googleWebSignInResults] の購読を開始する必要がある。
  Future<void> initializeGoogleSignIn();

  /// Web の GIS ボタン（renderButton）経由で完了したサインインの結果。
  ///
  /// null=成功、非 null=失敗した例外。Web 以外のプラットフォームでは利用しない。
  Stream<AuthException?> get googleWebSignInResults;
}

class AuthException implements Exception {
  const AuthException();
}

class AuthAccessDeniedException extends AuthException {
  const AuthAccessDeniedException();
}

/// サインアップ時の初期化（`users/{uid}` の生成、基本設計 §2.1）が
/// 完了していない状態。Auth Blocking Function の失敗を意味する。
class AuthSetupFailedException extends AuthException {
  const AuthSetupFailedException();
}

class AuthCancelledException extends AuthException {
  const AuthCancelledException();
}

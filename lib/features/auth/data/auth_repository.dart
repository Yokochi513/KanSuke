class AuthSession {
  const AuthSession({required this.uid});

  final String uid;
}

abstract interface class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

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

class AuthCancelledException extends AuthException {
  const AuthCancelledException();
}

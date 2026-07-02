class AuthSession {
  const AuthSession({required this.uid});

  final String uid;
}

abstract interface class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  Future<void> signOut();
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

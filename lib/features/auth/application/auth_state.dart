import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthStatus { signedOut, signedIn }

// NFR-4: 後続IssueでFirebase Authenticationの状態監視へ差し替える境界。
final authStateProvider = NotifierProvider<AuthStateNotifier, AuthStatus>(
  AuthStateNotifier.new,
);

class AuthStateNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.signedOut;

  void signInForPreview() => state = AuthStatus.signedIn;

  void signOutForPreview() => state = AuthStatus.signedOut;
}

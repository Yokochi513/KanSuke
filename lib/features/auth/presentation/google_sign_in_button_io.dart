import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_state.dart';

/// モバイル/デスクトップ向けの Google サインインボタン。
///
/// `authenticate()` を呼ぶ命令的フロー（[AuthActionController.signInWithGoogle]）。
class GoogleSignInButton extends ConsumerWidget {
  const GoogleSignInButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(authActionControllerProvider);
    final actions = ref.read(authActionControllerProvider.notifier);

    return FilledButton.icon(
      onPressed: actionState.isLoading ? null : actions.signInWithGoogle,
      icon: const Icon(Icons.login),
      label: const Text('Googleで続行'),
    );
  }
}

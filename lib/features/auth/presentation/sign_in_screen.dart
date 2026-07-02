import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_state.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key, this.initialErrorMessage});

  final String? initialErrorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(authActionControllerProvider);
    final errorMessage = actionState.errorMessage ?? initialErrorMessage;
    final actions = ref.read(authActionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('サインイン')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.calendar_month, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    'KanSuke',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  if (errorMessage != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: MaterialBanner(
                        content: Text(errorMessage),
                        actions: [
                          TextButton(
                            onPressed: actions.clearError,
                            child: const Text('閉じる'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: actionState.isLoading
                        ? null
                        : actions.signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Googleで続行'),
                  ),
                  if (ref.watch(appleSignInAvailableProvider)) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: actionState.isLoading
                          ? null
                          : actions.signInWithApple,
                      icon: const Icon(Icons.apple),
                      label: const Text('Appleでサインイン'),
                    ),
                  ],
                  if (actionState.isLoading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_state.dart';
import 'google_sign_in_button.dart';

/// アプリアイコンを円形に切り抜いた紋章。サインイン画面の顔として置く。
class _AppEmblem extends StatelessWidget {
  const _AppEmblem();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
        // アイコン自体が円形の枠を持つので、枠線と重ならないよう少し内側に置く。
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Image.asset(
            'assets/icon/app_icon.png',
            fit: BoxFit.cover,
            // 画像が読めなくてもサインインは続けられるようにする。
            errorBuilder: (context, _, _) =>
                Icon(Icons.calendar_month, size: 72, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

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
                  const _AppEmblem(),
                  const SizedBox(height: 20),
                  Text(
                    'KanSuke',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日程表',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 8,
                    ),
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
                  const GoogleSignInButton(),
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

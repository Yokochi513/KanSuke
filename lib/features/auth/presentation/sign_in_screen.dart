import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_state.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('サインイン')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            ref.read(authStateProvider.notifier).signInForPreview();
          },
          child: const Text('仮ログイン'),
        ),
      ),
    );
  }
}

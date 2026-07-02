import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Center(
        child: OutlinedButton(
          onPressed: () async {
            Navigator.popUntil(context, (route) => route.isFirst);
            await ref.read(authActionControllerProvider.notifier).signOut();
          },
          child: const Text('サインアウト'),
        ),
      ),
    );
  }
}

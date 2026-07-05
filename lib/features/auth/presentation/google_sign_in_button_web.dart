import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import '../application/auth_state.dart';

/// Web 向けの Google サインインボタン。
///
/// `google_sign_in` の Web 実装は `authenticate()` を持たないため、GIS が
/// 提供する公式ボタン（`renderButton()`）を描画する。ボタン押下で発火する
/// サインインは [AuthActionController.initializeGoogleWebSignIn] が購読する
/// `authenticationEvents` 経由で Firebase 認証に橋渡しされる。
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = ref
        .read(authActionControllerProvider.notifier)
        .initializeGoogleWebSignIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // GIS が描画する公式ボタン。クリックでアカウント選択が表示される。
        return web.renderButton();
      },
    );
  }
}

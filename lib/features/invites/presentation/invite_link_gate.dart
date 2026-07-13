import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigator_key.dart';
import '../../../app/routes.dart';
import '../../auth/application/auth_state.dart';
import '../application/invite_link.dart';
import '../application/invite_providers.dart';

/// 招待リンク（FR-9 / Issue #90）の受け口。
///
/// `MaterialApp` の `builder` に置き、Navigator より上でリンクを受ける:
/// - `kansuke://invite?token=...`（Web は `?token=...`）で起動されたら
///   トークンを [pendingInviteTokenProvider] に載せる。
/// - サインイン済みになった時点で受諾画面（[AppRoutes.inviteAccept]）を push する。
///   未サインインならサインインの完了を待つ（受諾には uid が要るため）。
///
/// 起動直後のリンク（コールドスタート）も、起動中に開かれたリンクも同じ経路で扱う。
class InviteLinkGate extends ConsumerStatefulWidget {
  const InviteLinkGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<InviteLinkGate> createState() => _InviteLinkGateState();
}

class _InviteLinkGateState extends ConsumerState<InviteLinkGate> {
  /// 受諾画面を表示中か。同じトークンで二重に push しないための番人。
  bool _showingAccept = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(inviteLinkStreamProvider, (_, next) {
      final uri = next.asData?.value;
      if (uri == null) return;
      final token = parseInviteToken(uri);
      if (token == null) return;
      ref.read(pendingInviteTokenProvider.notifier).state = token;
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(pendingInviteTokenProvider);
    final signedIn = ref.watch(currentUidProvider) != null;

    if (token == null) {
      _showingAccept = false;
    } else if (signedIn && !_showingAccept) {
      _showingAccept = true;
      // build 中に Navigator を触れないため、フレーム後に遷移する。
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAccept());
    }

    return widget.child;
  }

  void _openAccept() {
    final navigator = ref.read(navigatorKeyProvider).currentState;
    if (navigator == null) {
      _showingAccept = false;
      return;
    }
    navigator.pushNamed(AppRoutes.inviteAccept);
  }
}

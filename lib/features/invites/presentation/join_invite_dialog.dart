import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/invite_link.dart';
import '../application/invite_providers.dart';

/// 受け取った招待リンクを貼り付けて参加する導線（FR-9 / Issue #90）。
///
/// リンクを踏んでアプリが起動する経路（`kansuke://invite?token=...`）は Web では
/// 使えず（ブラウザからカスタムスキームは開けない）、モバイルでもメッセージアプリ
/// によってはリンクが開けないことがある。貼り付けはどの環境でも成立する受け口。
///
/// トークンを [pendingInviteTokenProvider] に載せると、リンクで起動したときと同じく
/// [InviteLinkGate] が受諾画面へ進める。
class JoinInviteDialog extends ConsumerStatefulWidget {
  const JoinInviteDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const JoinInviteDialog(),
    );
  }

  @override
  ConsumerState<JoinInviteDialog> createState() => _JoinInviteDialogState();
}

class _JoinInviteDialogState extends ConsumerState<JoinInviteDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('招待リンクで参加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('受け取った招待リンクを貼り付けてください。'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'kansuke://invite?token=...',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _join, child: const Text('確認')),
      ],
    );
  }

  void _join() {
    final token = parseInvitePaste(_controller.text);
    if (token == null) {
      setState(() => _error = '招待リンクを正しく貼り付けてください');
      return;
    }
    // 受諾画面（カレンダー名・招待者名の確認）は InviteLinkGate が開く。
    ref.read(pendingInviteTokenProvider.notifier).state = token;
    Navigator.pop(context);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendars/application/calendar_providers.dart';
import '../application/invite_providers.dart';
import '../data/invite_repository.dart';

/// 招待の受諾画面（FR-9 / Issue #90）。
///
/// 招待リンクで起動したときに [pendingInviteTokenProvider] 経由で開かれる。参加前に
/// カレンダー名と招待者名（`previewInvite`）を示し、参加/キャンセルを選ばせる。
/// 期限切れ・取り消し済み・使用済みのリンクはここで理由を表示して終わる。
class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key});

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(pendingInviteTokenProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('カレンダーへの招待'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '閉じる',
          onPressed: _accepting ? null : _close,
        ),
      ),
      body: token == null
          ? const _InviteMessage(
              icon: Icons.link_off,
              message: '招待リンクが見つかりませんでした。',
            )
          : ref
                .watch(invitePreviewProvider(token))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _InviteMessage(
                    icon: Icons.link_off,
                    message: error is InviteException
                        ? error.message
                        : '招待リンクを確認できませんでした。通信環境を確認してください。',
                    onClose: _close,
                  ),
                  data: (preview) => _buildPreview(token, preview),
                ),
    );
  }

  Widget _buildPreview(String token, InvitePreview preview) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              preview.invitedByName.isEmpty
                  ? 'カレンダーに招待されています'
                  : '${preview.invitedByName} さんから招待されています',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              preview.calendarName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (preview.alreadyMember) ...[
              const SizedBox(height: 12),
              Text(
                'すでにこのカレンダーに参加しています。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: _accepting ? null : () => _accept(token, preview),
              icon: const Icon(Icons.check),
              label: Text(preview.alreadyMember ? 'カレンダーを開く' : '参加する'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _accepting ? null : _close,
              child: const Text('キャンセル'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(String token, InvitePreview preview) async {
    setState(() => _accepting = true);
    try {
      final calendarId = await ref
          .read(inviteRepositoryProvider)
          .acceptInvite(token);
      // 参加したカレンダーを表示対象に切り替える（FR-8）。
      ref.read(calendarSelectionProvider.notifier).state = calendarId;
      if (!mounted) return;
      _close();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            preview.alreadyMember
                ? '「${preview.calendarName}」を開きました'
                : '「${preview.calendarName}」に参加しました',
          ),
        ),
      );
    } on InviteException catch (error) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// 受諾待ちを解除して画面を閉じる。同じリンクで再度開かれない限り戻らない。
  void _close() {
    ref.read(pendingInviteTokenProvider.notifier).state = null;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({
    required this.icon,
    required this.message,
    this.onClose,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onClose != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onClose, child: const Text('閉じる')),
            ],
          ],
        ),
      ),
    );
  }
}

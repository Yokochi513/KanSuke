import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../application/invite_link.dart';
import '../application/invite_providers.dart';
import '../data/invite_repository.dart';

/// カレンダー編集画面に置く招待リンクの節（FR-9 / Issue #90）。
///
/// - メンバーなら誰でも招待リンクを発行できる。
/// - 発行済みリンクを一覧し、発行者本人とオーナーが取り消せる。
///
/// トークン本体は発行時にしか得られない（Firestore にはハッシュしか無い）ため、
/// 発行直後にダイアログでリンクを見せ、コピーできるようにする。
class CalendarInvitesSection extends ConsumerStatefulWidget {
  const CalendarInvitesSection({required this.calendar, super.key});

  final Calendar calendar;

  @override
  ConsumerState<CalendarInvitesSection> createState() =>
      _CalendarInvitesSectionState();
}

class _CalendarInvitesSectionState
    extends ConsumerState<CalendarInvitesSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final invitesAsync = ref.watch(calendarInvitesProvider(widget.calendar.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('招待', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _createInvite,
            icon: const Icon(Icons.link),
            label: const Text('招待リンクを作成'),
          ),
        ),
        const SizedBox(height: 8),
        invitesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('招待リンクを読み込めませんでした。通信環境を確認してください。'),
          ),
          data: (invites) => _buildInvites(invites),
        ),
      ],
    );
  }

  Widget _buildInvites(List<IssuedInvite> invites) {
    if (invites.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('発行済みの招待リンクはありません'),
      );
    }

    final uid = ref.watch(currentUidProvider);
    final membersById = ref.watch(membersByIdProvider);
    final isOwner = widget.calendar.isOwnedBy(uid);

    return Column(
      children: [
        for (final invite in invites)
          ListTile(
            key: ValueKey(invite.id),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              invite.active ? Icons.link : Icons.link_off,
              color: invite.active ? null : Theme.of(context).disabledColor,
            ),
            title: Text(_statusOf(invite)),
            subtitle: Text(
              '発行: ${membersById[invite.invitedBy]?.name ?? '不明'}',
            ),
            // 取り消せるのは発行者本人とオーナーだけ（Functions 側でも検証する）。
            trailing: (invite.active && (isOwner || invite.invitedBy == uid))
                ? TextButton(
                    onPressed: _busy ? null : () => _revoke(invite),
                    child: const Text('取り消し'),
                  )
                : null,
          ),
      ],
    );
  }

  String _statusOf(IssuedInvite invite) {
    if (invite.revoked) return '取り消し済み';
    if (invite.usedCount >= invite.maxUses) return '使用済み';
    if (!invite.active) return '期限切れ';
    return '有効（${_formatExpiry(invite.expiresAt)}まで）';
  }

  String _formatExpiry(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _createInvite() async {
    setState(() => _busy = true);
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .createInvite(widget.calendar.id);
      ref.invalidate(calendarInvitesProvider(widget.calendar.id));
      if (!mounted) return;
      setState(() => _busy = false);
      await _showLink(invite);
    } on InviteException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack(error.message);
    }
  }

  /// 発行したリンクを見せる。ここで閉じるとトークンは二度と表示できない。
  Future<void> _showLink(CreatedInvite invite) async {
    final link = buildInviteLink(invite.token).toString();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('招待リンク'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(link),
            const SizedBox(height: 12),
            Text(
              '${_formatExpiry(invite.expiresAt)}まで有効（1回のみ使用可）。'
              'このリンクを知っている人は参加できます。家族にだけ送ってください。\n'
              'リンクを開いてもアプリが起動しない場合（Web など）は、'
              'カレンダー管理の「招待リンクで参加」に貼り付けてもらってください。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (!context.mounted) return;
              Navigator.pop(context);
              _showSnack('招待リンクをコピーしました');
            },
            icon: const Icon(Icons.copy),
            label: const Text('コピー'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(IssuedInvite invite) async {
    setState(() => _busy = true);
    try {
      await ref.read(inviteRepositoryProvider).revokeInvite(invite.id);
      ref.invalidate(calendarInvitesProvider(widget.calendar.id));
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('招待リンクを取り消しました');
    } on InviteException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack(error.message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

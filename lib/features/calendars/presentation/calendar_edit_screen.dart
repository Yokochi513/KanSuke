import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/color_utils.dart';
import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../invites/presentation/calendar_invites_section.dart';
import '../../users/application/user_providers.dart';
import '../application/calendar_providers.dart';
import '../data/calendar_membership_repository.dart';
import 'calendar_edit_args.dart';

/// カレンダー編集画面（FR-8 / Issue #89）。
///
/// 新規作成では名前だけを入力する（作成者が唯一のメンバー兼オーナーになり、
/// メンバーは招待リンクで増やす）。編集では以下を行う:
/// - カレンダー名の変更（オーナーのみ）
/// - メンバー一覧の表示、メンバーの削除・オーナー移譲（オーナーのみ）
/// - 自分の退出（オーナーは移譲するまで退出できない）
///
/// `memberIds` / `ownerId` はクライアントから直接書けないため、削除・退出・移譲は
/// Callable Function（[CalendarMembershipRepository]）経由で行う。
class CalendarEditScreen extends ConsumerStatefulWidget {
  const CalendarEditScreen({super.key});

  @override
  ConsumerState<CalendarEditScreen> createState() => _CalendarEditScreenState();
}

class _CalendarEditScreenState extends ConsumerState<CalendarEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _initialized = false;
  Calendar? _editing;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final arg = ModalRoute.of(context)?.settings.arguments;
    final args = arg is CalendarEditArgs
        ? arg
        : const CalendarEditArgs.create();

    final calendar = args.calendar;
    if (calendar != null) {
      _editing = calendar;
      _nameController.text = calendar.name;
    }
  }

  /// 表示に使うカレンダー。メンバーの削除・移譲の結果を反映するため、参加カレンダー
  /// 一覧の最新スナップショットを優先し、無ければ遷移時の引数を使う。
  Calendar? get _calendar {
    final editing = _editing;
    if (editing == null) return null;
    final calendars =
        ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
    return calendars.cast<Calendar?>().firstWhere(
      (calendar) => calendar?.id == editing.id,
      orElse: () => editing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _calendar;
    final isEditing = calendar != null;
    final uid = ref.watch(currentUidProvider);
    final isOwner = calendar?.isOwnedBy(uid) ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'カレンダーを編集' : '新規カレンダー')),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    enabled: isOwner,
                    decoration: InputDecoration(
                      labelText: 'カレンダー名',
                      border: const OutlineInputBorder(),
                      helperText: isOwner ? null : 'カレンダー名を変更できるのはオーナーだけです',
                    ),
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'カレンダー名を入力してください'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  if (calendar != null) ...[
                    _buildMembers(calendar, uid, isOwner: isOwner),
                    const SizedBox(height: 24),
                    // FR-9: メンバーを増やす唯一の手段（Issue #90）。
                    CalendarInvitesSection(calendar: calendar),
                    const SizedBox(height: 24),
                    _buildLeaveButton(calendar),
                  ],
                ],
              ),
            ),
          ),
          if (isOwner)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(isEditing ? '保存' : '作成'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// メンバー一覧（FR-2 の識別色付き）。オーナーはメンバーの削除・オーナー移譲ができる。
  Widget _buildMembers(
    Calendar calendar,
    String? uid, {
    required bool isOwner,
  }) {
    final membersById = ref.watch(membersByIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('参加者', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final memberId in calendar.memberIds)
          _buildMemberTile(
            calendar: calendar,
            memberId: memberId,
            member: membersById[memberId],
            isSelf: memberId == uid,
            isOwner: isOwner,
          ),
      ],
    );
  }

  Widget _buildMemberTile({
    required Calendar calendar,
    required String memberId,
    required User? member,
    required bool isSelf,
    required bool isOwner,
  }) {
    // メンバーのドキュメントが届く前（初回同期中）は uid で場所だけ確保する。
    final name = member?.name ?? '(読み込み中)';
    final isMemberOwner = calendar.ownerId == memberId;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: member == null
            ? Theme.of(context).disabledColor
            : colorFromHex(member.color),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          if (isMemberOwner) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('オーナー'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: isSelf ? const Text('あなた') : null,
      trailing: (isOwner && !isSelf && !_saving)
          ? PopupMenuButton<_MemberAction>(
              tooltip: 'メンバーの操作',
              onSelected: (action) => switch (action) {
                _MemberAction.transferOwnership => _confirmTransferOwnership(
                  calendar,
                  memberId,
                  name,
                ),
                _MemberAction.remove => _confirmRemoveMember(
                  calendar,
                  memberId,
                  name,
                ),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MemberAction.transferOwnership,
                  child: Text('オーナーにする'),
                ),
                PopupMenuItem(
                  value: _MemberAction.remove,
                  child: Text('カレンダーから削除'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildLeaveButton(Calendar calendar) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : () => _confirmLeave(calendar),
        icon: const Icon(Icons.logout),
        label: const Text('このカレンダーから退出'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  Future<void> _confirmRemoveMember(
    Calendar calendar,
    String memberId,
    String name,
  ) async {
    final confirmed = await _confirm(
      title: 'メンバーを削除',
      message: '$name さんをこのカレンダーから削除します。よろしいですか？',
      action: '削除',
    );
    if (!confirmed) return;
    await _runMembership(
      () => ref
          .read(calendarMembershipRepositoryProvider)
          .removeMember(calendarId: calendar.id, uid: memberId),
      success: '$name さんを削除しました',
    );
  }

  Future<void> _confirmTransferOwnership(
    Calendar calendar,
    String memberId,
    String name,
  ) async {
    final confirmed = await _confirm(
      title: 'オーナーを移譲',
      message: '$name さんをオーナーにします。以後、カレンダー名の変更やメンバーの削除はできなくなります。',
      action: '移譲',
    );
    if (!confirmed) return;
    await _runMembership(
      () => ref
          .read(calendarMembershipRepositoryProvider)
          .transferOwnership(calendarId: calendar.id, uid: memberId),
      success: 'オーナーを $name さんに移譲しました',
    );
  }

  Future<void> _confirmLeave(Calendar calendar) async {
    final confirmed = await _confirm(
      title: 'カレンダーから退出',
      message: '「${calendar.name}」から退出します。以後このカレンダーの予定は見られなくなります。',
      action: '退出',
    );
    if (!confirmed) return;
    final left = await _runMembership(
      () => ref
          .read(calendarMembershipRepositoryProvider)
          .leaveCalendar(calendar.id),
      success: '「${calendar.name}」から退出しました',
    );
    if (left && mounted) Navigator.pop(context);
  }

  /// メンバー操作（Callable）を実行し、結果をスナックバーで知らせる。
  /// 拒否理由（オーナーは退出できない等）は Functions のメッセージをそのまま出す。
  Future<bool> _runMembership(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(success);
      }
      return true;
    } on CalendarMembershipException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(error.message);
      }
      return false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('サインインが必要です');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(calendarRepositoryProvider);
    final name = _nameController.text.trim();

    try {
      final editing = _editing;
      if (editing == null) {
        // 作成者が唯一のメンバー兼オーナー。メンバーは招待リンクで増やす。
        final calendar = Calendar.create(
          name: name,
          memberIds: [uid],
          creatorId: uid,
          now: DateTime.now(),
        );
        await repository.create(calendar);
      } else {
        await repository.updateName(editing.id, name);
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to save calendar (editing=${_editing?.id})',
        tag: 'CalendarEditScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('保存に失敗しました。通信環境を確認してください。');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _MemberAction { transferOwnership, remove }

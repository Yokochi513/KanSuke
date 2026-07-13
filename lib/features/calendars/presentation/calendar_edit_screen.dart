import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../application/calendar_providers.dart';
import 'calendar_edit_args.dart';

/// カレンダー編集画面（FR-8）。名前と参加者（家族メンバーの複数選択）の
/// 作成・編集を行う。カレンダーの削除はスコープ外。
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
  final Set<String> _memberIds = {};
  // 編集画面を開いた時点のメンバー集合。保存時にここからの差分だけを
  // サーバーへ送ることで、開いてから保存するまでの間に他デバイスが加えた
  // 変更を上書きしないようにする（[CalendarRepository.updateNameAndMembers]）。
  Set<String> _originalMemberIds = const {};
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
      _memberIds.addAll(calendar.memberIds);
      _originalMemberIds = Set.of(calendar.memberIds);
    } else {
      final uid = ref.read(currentUidProvider);
      if (uid != null) {
        _memberIds.add(uid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);
    final members = membersAsync.asData?.value ?? const [];
    final isEditing = _editing != null;

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
                    decoration: const InputDecoration(
                      labelText: 'カレンダー名',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'カレンダー名を入力してください'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildMembersField(members),
                ],
              ),
            ),
          ),
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

  /// 参加者の複数選択（FR-8）。サインアップ済みのメンバーからのみ選択でき、
  /// 1人以上の選択を必須とする。
  Widget _buildMembersField(List<User> members) {
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }
    return FormField<Set<String>>(
      initialValue: _memberIds,
      validator: (value) =>
          (value == null || value.isEmpty) ? '参加者を1人以上選択してください' : null,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('参加者'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final member in members)
                  FilterChip(
                    label: Text(member.name),
                    selected: _memberIds.contains(member.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _memberIds.add(member.id);
                      } else {
                        _memberIds.remove(member.id);
                      }
                      field.didChange(_memberIds);
                    }),
                  ),
              ],
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
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
    final memberIds = _memberIds.toList()..sort();
    final name = _nameController.text.trim();

    try {
      final editing = _editing;
      if (editing == null) {
        final calendar = Calendar.create(
          name: name,
          memberIds: memberIds,
          creatorId: uid,
          now: DateTime.now(),
        );
        await repository.create(calendar);
      } else {
        await repository.updateNameAndMembers(
          editing.id,
          name: name,
          addedMemberIds: _memberIds.difference(_originalMemberIds),
          removedMemberIds: _originalMemberIds.difference(_memberIds),
        );
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

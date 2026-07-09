import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../application/event_providers.dart';
import 'event_edit_args.dart';

/// 「開始 n 分前」のリマインド候補（FR-5）。値は分。
const _reminderPresets = <int, String>{
  10: '10分前',
  30: '30分前',
  60: '1時間前',
  180: '3時間前',
  1440: '1日前',
};

/// 予定編集画面（FR-1 / FR-3 / FR-5、基本設計 §6.1・§6.3・§3.2）。
///
/// 予定の作成・編集・ソフト削除を行う。仮↔確定はトグル1操作で切替、
/// リマインドは `reminderOffsets` の保存まで（実配信は Functions・別Issue）。
class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key});

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _memoController = TextEditingController();

  bool _initialized = false;
  Event? _editing; // 編集対象（新規は null）
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _allDay = false;
  EventType _type = EventType.tentative;
  final Set<String> _participantIds = {};
  final Set<int> _reminderOffsets = {};
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// ルート引数から初回のみ状態を組み立てる（依存が揃う didChangeDependencies で）。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final arg = ModalRoute.of(context)?.settings.arguments;
    final args = arg is EventEditArgs
        ? arg
        : EventEditArgs.create(DateUtils.dateOnly(DateTime.now()));

    final event = args.event;
    if (event != null) {
      _editing = event;
      _titleController.text = event.title;
      _memoController.text = event.memo;
      _allDay = event.allDay;
      _type = event.type;
      _participantIds.addAll(event.participantIds);
      final start = event.startAt.toLocal();
      final end = event.endAt.toLocal();
      _startDate = DateUtils.dateOnly(start);
      _endDate = DateUtils.dateOnly(end);
      _startTime = TimeOfDay.fromDateTime(start);
      _endTime = TimeOfDay.fromDateTime(end);
      _reminderOffsets.addAll(event.reminderOffsets);
    } else {
      _startDate = DateUtils.dateOnly(args.initialDate!);
      _endDate = _startDate;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
      final uid = ref.read(currentUidProvider);
      if (uid != null) {
        _participantIds.add(uid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(familyMembersProvider).asData?.value ?? const [];
    final isEditing = _editing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '予定を編集' : '新規作成'),
        actions: [
          if (isEditing)
            IconButton(
              tooltip: '削除',
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'タイトル',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'タイトルを入力してください'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTypeToggle(),
                  const SizedBox(height: 8),
                  _buildParticipantsField(members),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('終日'),
                    value: _allDay,
                    onChanged: (value) => setState(() => _allDay = value),
                  ),
                  _buildDateTimeFields(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _memoController,
                    decoration: const InputDecoration(
                      labelText: 'メモ（任意）',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _buildReminderField(),
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

  Widget _buildTypeToggle() {
    return SegmentedButton<EventType>(
      segments: const [
        ButtonSegment(value: EventType.tentative, label: Text('仮')),
        ButtonSegment(value: EventType.confirmed, label: Text('確定')),
      ],
      selected: {_type},
      onSelectionChanged: (selection) =>
          setState(() => _type = selection.first),
    );
  }

  /// 参加者の複数選択（FR-1・FR-2、基本設計 §6.1・§6.3）。1人以上の選択を必須とする。
  Widget _buildParticipantsField(List<User> members) {
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }
    return FormField<Set<String>>(
      initialValue: _participantIds,
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
                    selected: _participantIds.contains(member.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _participantIds.add(member.id);
                      } else {
                        _participantIds.remove(member.id);
                      }
                      field.didChange(_participantIds);
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

  Widget _buildDateTimeFields() {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('開始日'),
          trailing: Text(_formatDate(_startDate)),
          onTap: () => _pickDate(isStart: true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('終了日'),
          trailing: Text(_formatDate(_endDate)),
          onTap: () => _pickDate(isStart: false),
        ),
        if (!_allDay) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('開始時刻'),
            trailing: Text(_formatTime(_startTime)),
            onTap: () => _pickTime(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('終了時刻'),
            trailing: Text(_formatTime(_endTime)),
            onTap: () => _pickTime(isStart: false),
          ),
        ],
      ],
    );
  }

  Widget _buildReminderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('リマインド'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in _reminderPresets.entries)
              FilterChip(
                label: Text(entry.value),
                selected: _reminderOffsets.contains(entry.key),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _reminderOffsets.add(entry.key);
                  } else {
                    _reminderOffsets.remove(entry.key);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked != null) {
      final pickedDate = DateUtils.dateOnly(picked);
      setState(() {
        if (isStart) {
          _startDate = pickedDate;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = pickedDate;
        }
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initialTime = isStart ? _startTime : _endTime;
    final baseDate = isStart ? _startDate : _endDate;
    final picked = await showCupertinoModalPopup<TimeOfDay>(
      context: context,
      builder: (context) {
        final initialDateTime = DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
          initialTime.hour,
          initialTime.minute,
        );
        var selectedDateTime = initialDateTime;

        return _TimePickerSheet(
          title: isStart ? '開始時刻' : '終了時刻',
          initialDateTime: initialDateTime,
          onDateTimeChanged: (value) => selectedDateTime = value,
          onCancel: () => Navigator.pop(context),
          onDone: () =>
              Navigator.pop(context, TimeOfDay.fromDateTime(selectedDateTime)),
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _setStartTimeKeepingDuration(picked);
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _setStartTimeKeepingDuration(TimeOfDay picked) {
    final currentDuration = _endAt.difference(_startAt);
    final durationToKeep = currentDuration.isNegative
        ? Duration.zero
        : currentDuration;

    _startTime = picked;
    final shiftedEndAt = _startAt.add(durationToKeep);

    // NFR-1 / Issue #55: 開始時刻だけを動かしたい操作では、設定済みの時間幅を保つ。
    _endDate = DateUtils.dateOnly(shiftedEndAt);
    _endTime = TimeOfDay.fromDateTime(shiftedEndAt);
  }

  DateTime get _startAt => _allDay
      ? _startDate
      : DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          _startTime.hour,
          _startTime.minute,
        );

  DateTime get _endAt => _allDay
      ? _endDate
      : DateTime(
          _endDate.year,
          _endDate.month,
          _endDate.day,
          _endTime.hour,
          _endTime.minute,
        );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endAt.isBefore(_startAt)) {
      _showSnack(_allDay ? '終了日は開始日以降にしてください' : '終了は開始日時以降にしてください');
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('サインインが必要です');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(eventRepositoryProvider);
    final offsets = _reminderOffsets.toList()..sort();
    final participantIds = _participantIds.toList()..sort();

    try {
      final editing = _editing;
      if (editing == null) {
        final event = Event.create(
          title: _titleController.text.trim(),
          creatorId: uid,
          participantIds: participantIds,
          startAt: _startAt,
          endAt: _endAt,
          allDay: _allDay,
          type: _type,
          memo: _memoController.text.trim(),
          reminderOffsets: offsets,
          updatedBy: uid,
          now: DateTime.now(),
        );
        await repository.create(event, updatedBy: uid);
      } else {
        final updated = editing.copyWith(
          title: _titleController.text.trim(),
          participantIds: participantIds,
          startAt: _startAt,
          endAt: _endAt,
          allDay: _allDay,
          type: _type,
          memo: _memoController.text.trim(),
          reminderOffsets: offsets,
        );
        await repository.update(updated, updatedBy: uid);
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to save event (editing=${_editing?.id})',
        tag: 'EventEditScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('保存に失敗しました。通信環境を確認してください。');
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('予定を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('サインインが必要です');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(eventRepositoryProvider)
          .softDelete(_editing!.id, updatedBy: uid);
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to delete event ${_editing?.id}',
        tag: 'EventEditScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('削除に失敗しました。通信環境を確認してください。');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // NFR-1: 「英語圏の表記」に見えるという指摘（Issue #58）を受け、
  // スラッシュ区切りではなく年月日＋曜日の日本語表記にする。
  static const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

  String _formatDate(DateTime day) =>
      '${day.year}年${day.month}月${day.day}日'
      '（${_weekdayLabels[day.weekday - 1]}）';

  String _formatTime(TimeOfDay time) =>
      '${_two(time.hour)}:${_two(time.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _TimePickerSheet extends StatelessWidget {
  const _TimePickerSheet({
    required this.title,
    required this.initialDateTime,
    required this.onDateTimeChanged,
    required this.onCancel,
    required this.onDone,
  });

  final String title;
  final DateTime initialDateTime;
  final ValueChanged<DateTime> onDateTimeChanged;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 320,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  CupertinoButton(
                    onPressed: onCancel,
                    child: const Text('キャンセル'),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                  ),
                  CupertinoButton(onPressed: onDone, child: const Text('完了')),
                ],
              ),
            ),
            Expanded(
              // NFR-1: iPhoneでの時刻指定を軽くするため、時計盤ではなく縦スクロールの24時間ピッカーにする。
              // 既定の ScrollBehavior はマウスでのドラッグ操作を許可しない
              // （マウスホイールでの回転のみ）ため、クリックしたまま上下に
              // 流す操作もできるよう明示的に許可する。
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialDateTime,
                  minuteInterval: 1,
                  use24hFormat: true,
                  showTimeSeparator: true,
                  backgroundColor: theme.colorScheme.surface,
                  onDateTimeChanged: onDateTimeChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

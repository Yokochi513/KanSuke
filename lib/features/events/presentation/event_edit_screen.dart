import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
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

enum _RecurrenceFrequencyOption { none, weekly, monthly, yearly }

enum _RecurrenceCountMode { infinite, specified }

/// 予定編集画面（FR-1 / FR-3 / FR-5、基本設計 §6.1・§6.3・§3.2）。
///
/// 予定の作成・編集・ソフト削除を行う。仮↔確定はトグル1操作で切替、
/// リマインドは各自が自分の分だけ設定する（`reminderOffsets` は uid → 分の map。
/// 実配信は Functions の onEventWrite / sendDueReminders、Issue #14）。
class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key});

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _memoController = TextEditingController();
  final _recurrenceCountController = TextEditingController(text: '10');

  bool _initialized = false;
  Event? _editing; // 編集対象（新規は null）
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _allDay = false;
  EventType _type = EventType.tentative;
  late String _calendarId;
  final Set<String> _participantIds = {};

  /// リマインドの設定（uid → 開始 n 分前）。FR-5 / Issue #14。
  ///
  /// 画面で編集できるのは**自分の分だけ**（通知は設定した本人にしか届かない）。
  /// 他のメンバーの設定は編集時にそのまま引き継ぐ。
  final Map<String, Set<int>> _reminderOffsets = {};
  _RecurrenceFrequencyOption _recurrenceOption =
      _RecurrenceFrequencyOption.none;
  _RecurrenceCountMode _recurrenceCountMode = _RecurrenceCountMode.infinite;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    _recurrenceCountController.dispose();
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
      final editingEvent = event.masterEventForEditing;
      _editing = editingEvent;
      _prefillFrom(editingEvent);
      _setRecurrenceState(editingEvent);
    } else {
      _startDate = DateUtils.dateOnly(args.initialDate!);
      _endDate = _startDate;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
      // FR-8: 新規作成時は、遷移元で表示していたカレンダーを初期値にする。
      _calendarId = ref.read(selectedCalendarIdProvider);
      if (_calendarId.isEmpty) {
        // カレンダー一覧がまだ届いていない間は表示中カレンダーが定まらない
        // （空文字）。確定したら初期値として反映する。
        ref.listenManual(selectedCalendarIdProvider, (_, calendarId) {
          if (_calendarId.isEmpty && calendarId.isNotEmpty) {
            setState(() => _calendarId = calendarId);
          }
        });
      }
      final uid = ref.read(currentUidProvider);
      if (uid != null) {
        _participantIds.add(uid);
      }
    }
  }

  /// 既存予定 [event] の属性でフォームの初期値を埋める（編集・コピー共通）。
  /// くり返し設定は呼び出し側で扱う（編集は引き継ぎ、コピーは破棄する）。
  void _prefillFrom(Event event) {
    _titleController.text = event.title;
    _memoController.text = event.memo;
    _allDay = event.allDay;
    _type = event.type;
    _calendarId = event.calendarId;
    _participantIds.addAll(event.participantIds);
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    _startDate = DateUtils.dateOnly(start);
    _endDate = DateUtils.dateOnly(end);
    _startTime = TimeOfDay.fromDateTime(start);
    _endTime = TimeOfDay.fromDateTime(end);
    for (final entry in event.reminderOffsets.entries) {
      _reminderOffsets[entry.key] = entry.value.toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider);
    final members = membersAsync.asData?.value ?? const [];
    final calendars = ref.watch(myCalendarsProvider).asData?.value ?? const [];
    final isEditing = _editing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '予定を編集' : '新規作成'),
        actions: [
          if (isEditing) ...[
            IconButton(
              tooltip: 'コピー',
              onPressed: _saving ? null : _copyEvent,
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              tooltip: '削除',
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
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
                  _buildCalendarField(calendars),
                  const SizedBox(height: 16),
                  _buildTypeToggle(),
                  const SizedBox(height: 8),
                  _buildParticipantsField(_eligibleMembers(members, calendars)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('終日'),
                    value: _allDay,
                    onChanged: (value) => setState(() => _allDay = value),
                  ),
                  _buildDateTimeFields(),
                  const SizedBox(height: 16),
                  _buildRecurrenceFields(),
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
                  _buildReminderField(membersAsync),
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

  /// FR-1: 作成者は予定作成時に固定される監査情報なので、編集時は小さく読み取り専用で示す。
  Widget _buildCreatorCaption(AsyncValue<List<User>> membersAsync) {
    final editing = _editing;
    if (editing == null) return const SizedBox.shrink();

    final creatorName = membersAsync.when(
      data: (members) => _creatorName(members, editing.creatorId),
      loading: () => '読み込み中',
      error: (_, _) => '作成者を取得できません',
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '作成者: $creatorName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  String _creatorName(List<User> members, String creatorId) {
    for (final member in members) {
      if (member.id == creatorId) {
        return member.name;
      }
    }
    return '不明な作成者';
  }

  /// カレンダー選択（FR-8）。参加者候補は選択中カレンダーの参加者に限定する。
  Widget _buildCalendarField(List<Calendar> calendars) {
    if (calendars.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasSelection = calendars.any(
      (calendar) => calendar.id == _calendarId,
    );
    return DropdownButtonFormField<String>(
      initialValue: hasSelection ? _calendarId : null,
      decoration: const InputDecoration(
        labelText: 'カレンダー',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final calendar in calendars)
          DropdownMenuItem(value: calendar.id, child: Text(calendar.name)),
      ],
      onChanged: (value) {
        if (value == null) return;
        final calendar = calendars.firstWhere(
          (calendar) => calendar.id == value,
        );
        setState(() {
          _calendarId = value;
          // FR-8: カレンダー変更後は、新しいカレンダーの参加者ではない
          // メンバーを選択から外す。
          _participantIds.removeWhere((id) => !calendar.memberIds.contains(id));
        });
      },
    );
  }

  /// 参加者候補を選択中カレンダーの参加者に限定する（FR-8）。カレンダーが
  /// まだ読み込み中・未選択の間は全家族メンバーを候補にする。
  List<User> _eligibleMembers(List<User> members, List<Calendar> calendars) {
    final index = calendars.indexWhere(
      (calendar) => calendar.id == _calendarId,
    );
    if (index == -1) return members;
    final memberIds = calendars[index].memberIds;
    return members.where((member) => memberIds.contains(member.id)).toList();
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

  Widget _buildRecurrenceFields() {
    return Column(
      children: [
        DropdownButtonFormField<_RecurrenceFrequencyOption>(
          initialValue: _recurrenceOption,
          decoration: const InputDecoration(
            labelText: 'くり返し設定',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: _RecurrenceFrequencyOption.none,
              child: Text('なし'),
            ),
            DropdownMenuItem(
              value: _RecurrenceFrequencyOption.weekly,
              child: Text('毎週'),
            ),
            DropdownMenuItem(
              value: _RecurrenceFrequencyOption.monthly,
              child: Text('毎月'),
            ),
            DropdownMenuItem(
              value: _RecurrenceFrequencyOption.yearly,
              child: Text('毎年'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _recurrenceOption = value);
          },
        ),
        if (_recurrenceOption != _RecurrenceFrequencyOption.none) ...[
          const SizedBox(height: 16),
          SegmentedButton<_RecurrenceCountMode>(
            segments: const [
              ButtonSegment(
                value: _RecurrenceCountMode.infinite,
                label: Text('無限'),
              ),
              ButtonSegment(
                value: _RecurrenceCountMode.specified,
                label: Text('回数指定'),
              ),
            ],
            selected: {_recurrenceCountMode},
            onSelectionChanged: (selection) =>
                setState(() => _recurrenceCountMode = selection.first),
          ),
          if (_recurrenceCountMode == _RecurrenceCountMode.specified) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _recurrenceCountController,
              decoration: const InputDecoration(
                labelText: '回数',
                suffixText: '回',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: _validateRecurrenceCount,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildReminderField(AsyncValue<List<User>> membersAsync) {
    // FR-5 / Issue #14: リマインドは各自が自分の分だけ設定する。通知は設定した
    // 本人にしか届かないため、他のメンバーの設定はここに出さず、保存時も温存する。
    final uid = ref.watch(currentUidProvider);
    final mine = uid == null
        ? const <int>{}
        : (_reminderOffsets[uid] ?? const <int>{});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('リマインド（自分の通知）'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in _reminderPresets.entries)
              FilterChip(
                label: Text(entry.value),
                selected: mine.contains(entry.key),
                onSelected: uid == null
                    ? null
                    : (selected) => setState(() {
                        final offsets = _reminderOffsets.putIfAbsent(
                          uid,
                          () => <int>{},
                        );
                        if (selected) {
                          offsets.add(entry.key);
                        } else {
                          offsets.remove(entry.key);
                        }
                      }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'ほかのメンバーには、その人が設定したリマインドだけが届きます',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _buildCreatorCaption(membersAsync),
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

  /// 保存用のリマインド設定（uid → 開始 n 分前）。空の uid は残さない。
  Map<String, List<int>> _reminderOffsetsForSave() {
    return {
      for (final entry in _reminderOffsets.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.toList()..sort(),
    };
  }

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
    final offsets = _reminderOffsetsForSave();
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
          calendarId: _calendarId,
          recurrenceFrequency: _recurrenceFrequencyForSave(),
          recurrenceCount: _recurrenceCountForSave(),
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
          calendarId: _calendarId,
          memo: _memoController.text.trim(),
          reminderOffsets: offsets,
          recurrenceFrequency: _recurrenceFrequencyForSave(),
          recurrenceCount: _recurrenceCountForSave(),
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

  void _setRecurrenceState(Event event) {
    _recurrenceOption = switch (event.recurrenceFrequency) {
      null => _RecurrenceFrequencyOption.none,
      EventRecurrenceFrequency.weekly => _RecurrenceFrequencyOption.weekly,
      EventRecurrenceFrequency.monthly => _RecurrenceFrequencyOption.monthly,
      EventRecurrenceFrequency.yearly => _RecurrenceFrequencyOption.yearly,
    };

    final recurrenceCount = event.recurrenceCount;
    if (event.recurrenceFrequency != null && recurrenceCount != null) {
      _recurrenceCountMode = _RecurrenceCountMode.specified;
      _recurrenceCountController.text = recurrenceCount.toString();
    } else {
      _recurrenceCountMode = _RecurrenceCountMode.infinite;
    }
  }

  EventRecurrenceFrequency? _recurrenceFrequencyForSave() {
    return switch (_recurrenceOption) {
      _RecurrenceFrequencyOption.none => null,
      _RecurrenceFrequencyOption.weekly => EventRecurrenceFrequency.weekly,
      _RecurrenceFrequencyOption.monthly => EventRecurrenceFrequency.monthly,
      _RecurrenceFrequencyOption.yearly => EventRecurrenceFrequency.yearly,
    };
  }

  int? _recurrenceCountForSave() {
    if (_recurrenceOption == _RecurrenceFrequencyOption.none ||
        _recurrenceCountMode == _RecurrenceCountMode.infinite) {
      return null;
    }
    return int.tryParse(_recurrenceCountController.text.trim());
  }

  String? _validateRecurrenceCount(String? value) {
    if (_recurrenceOption == _RecurrenceFrequencyOption.none ||
        _recurrenceCountMode == _RecurrenceCountMode.infinite) {
      return null;
    }
    final text = value?.trim() ?? '';
    // ユーザー入力は文字列なので、int 変換に失敗する境界を明示して止める。
    final count = int.tryParse(text);
    if (count == null) {
      return '回数を半角数字で入力してください';
    }
    if (count <= 0) {
      return '回数は1以上で入力してください';
    }
    return null;
  }

  /// FR-1 / #75: 編集中の予定をひな形に、コピー先の日付をカレンダーで複数選び、
  /// 選んだ各日へ単発予定として一括複製する。日付だけを選んだ日へ移動し、
  /// 時刻・時間幅・その他の属性は引き継ぐ。各複製に新しい UUID が発番され、
  /// 元予定は変更されず、繰り返し設定は引き継がない（展開インスタンス由来でも
  /// 単発予定になる）。飛び飛びの日程（不定期イベント）を一度に配置できる。
  Future<void> _copyEvent() async {
    final source = _editing;
    if (source == null) return;

    final sourceStart = source.startAt.toLocal();
    final dates = await showDialog<List<DateTime>>(
      context: context,
      builder: (context) =>
          _CopyDatesPicker(initialDay: DateUtils.dateOnly(sourceStart)),
    );
    if (dates == null || dates.isEmpty) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _showSnack('サインインが必要です');
      return;
    }

    // 各日へ移動する。終日はその日付、時刻ありは元と同じ時刻に置き、終了は
    // 所要時間を保って算出する。
    final duration = source.endAt.difference(source.startAt);
    setState(() => _saving = true);
    try {
      final repository = ref.read(eventRepositoryProvider);
      for (final date in dates) {
        final newStart = source.allDay
            ? DateUtils.dateOnly(date)
            : DateTime(
                date.year,
                date.month,
                date.day,
                sourceStart.hour,
                sourceStart.minute,
              );
        final copy = Event.create(
          title: source.title,
          creatorId: uid,
          participantIds: source.participantIds.toList(),
          startAt: newStart,
          endAt: newStart.add(duration),
          allDay: source.allDay,
          type: source.type,
          memo: source.memo,
          reminderOffsets: {
            for (final entry in source.reminderOffsets.entries)
              entry.key: entry.value.toList(),
          },
          updatedBy: uid,
          now: DateTime.now(),
          calendarId: source.calendarId,
        );
        await repository.create(copy, updatedBy: uid);
      }
      if (mounted) {
        setState(() => _saving = false);
        _showSnack(
          dates.length == 1
              ? '${_formatDate(dates.first)}にコピーしました'
              : '${dates.length}件の予定をコピーしました',
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to copy event ${source.id}',
        tag: 'EventEditScreen',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('コピーに失敗しました。通信環境を確認してください。');
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

/// コピー先の複数日を選ぶダイアログ（#75）。
///
/// 月カレンダー（[TableCalendar]）で任意の日をタップして複数選択・解除し、
/// 「N件コピー」で確定すると選んだ日付一覧（昇順）を返す。キャンセル時は null。
/// 飛び飛びの日程（不定期イベント）にも配置できるよう、範囲ではなく任意の
/// 複数日を選べるようにする。
class _CopyDatesPicker extends StatefulWidget {
  const _CopyDatesPicker({required this.initialDay});

  final DateTime initialDay;

  @override
  State<_CopyDatesPicker> createState() => _CopyDatesPickerState();
}

class _CopyDatesPickerState extends State<_CopyDatesPicker> {
  late DateTime _focusedDay;
  // 選択済みの日（[DateUtils.dateOnly] で正規化）。
  final List<DateTime> _selectedDays = [];

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDay;
  }

  void _toggle(DateTime day) {
    final key = DateUtils.dateOnly(day);
    setState(() {
      final index = _selectedDays.indexWhere((d) => isSameDay(d, key));
      if (index >= 0) {
        _selectedDays.removeAt(index);
      } else {
        _selectedDays.add(key);
      }
      _focusedDay = day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = _selectedDays.length;
    return AlertDialog(
      title: const Text('コピー先の日付を選択'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 360,
        child: TableCalendar<void>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2035, 12, 31),
          focusedDay: _focusedDay,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: '月'},
          selectedDayPredicate: (day) =>
              _selectedDays.any((d) => isSameDay(d, day)),
          onDaySelected: (selectedDay, _) => _toggle(selectedDay),
          onPageChanged: (focusedDay) => _focusedDay = focusedDay,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          // 1 件も選ばれていなければ確定できない。
          onPressed: count == 0
              ? null
              : () => Navigator.pop(context, _selectedDays.toList()..sort()),
          child: Text('$count件コピー'),
        ),
      ],
    );
  }
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

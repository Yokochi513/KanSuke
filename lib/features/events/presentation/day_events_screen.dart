import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../core/color_utils.dart';
import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
import '../../calendars/presentation/calendar_switcher.dart';
import '../../users/application/user_providers.dart';
import '../application/event_ordering.dart';
import '../application/event_providers.dart';
import 'event_edit_args.dart';
import 'event_type_badge.dart';

/// 日別予定一覧（FR-1 / FR-2 / FR-3、基本設計 §6.1）。
///
/// 選択日の予定を参加者の色・種別バッジ・時刻・メモ付きで表示し、各項目や
/// 新規作成から予定編集画面（#11）へ遷移する。対象日はルート引数（[DateTime]）
/// で受け取る。
///
/// ヘッダー（AppBar「日別予定」）は固定のまま、日付見出しと一覧部分だけを
/// [PageView] で横スクロール切り替えする（Issue #67）。前後日への移動を
/// 新規画面遷移にすると開閉アニメーションが不自然になるため、同一画面内の
/// ページ送りにしている。
class DayEventsScreen extends ConsumerStatefulWidget {
  const DayEventsScreen({super.key});

  @override
  ConsumerState<DayEventsScreen> createState() => _DayEventsScreenState();
}

class _DayEventsScreenState extends ConsumerState<DayEventsScreen> {
  // ルート引数で渡された日を中心に、前後 約136 年分のページ数を確保する。
  // 実運用でこの範囲を使い切ることはない。
  static const int _centerPage = 50000;
  static const int _pageCount = _centerPage * 2 + 1;

  bool _initialized = false;
  late DateTime _baseDay;
  late final PageController _pageController;
  int _currentPage = _centerPage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final arg = ModalRoute.of(context)?.settings.arguments;
    _baseDay = arg is DateTime
        ? DateUtils.dateOnly(arg)
        : DateUtils.dateOnly(DateTime.now());
    _pageController = PageController(initialPage: _centerPage);
    _initialized = true;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dayForPage(int page) =>
      _addCalendarDays(_baseDay, page - _centerPage);

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDay = _dayForPage(_currentPage);
    return Scaffold(
      appBar: AppBar(title: const CalendarSwitcherTitle()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.eventEdit,
          arguments: EventEditArgs.create(currentDay),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新規作成'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _pageCount,
        onPageChanged: (page) => setState(() => _currentPage = page),
        itemBuilder: (context, page) {
          final day = _dayForPage(page);
          return _DayPage(
            day: day,
            onPreviousDay: () => _goToPage(page - 1),
            onNextDay: () => _goToPage(page + 1),
          );
        },
      ),
    );
  }
}

/// 1 日分の日付見出し＋予定一覧（[DayEventsScreen] の [PageView] の 1 ページ）。
class _DayPage extends ConsumerWidget {
  const _DayPage({
    required this.day,
    required this.onPreviousDay,
    required this.onNextDay,
  });

  final DateTime day;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextDay = day.add(const Duration(days: 1));
    final calendarId = ref.watch(selectedCalendarIdProvider);
    final eventsAsync = ref.watch(
      eventsInRangeProvider((start: day, end: nextDay, calendarId: calendarId)),
    );
    final membersById = ref.watch(membersByIdProvider);
    final currentUid = ref.watch(currentUidProvider);

    return Column(
      children: [
        _DayNavigationHeader(
          day: day,
          onPreviousDay: onPreviousDay,
          onNextDay: onNextDay,
        ),
        const Divider(height: 1),
        Expanded(
          child: eventsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              AppLogger.error(
                'eventsInRangeProvider errored for $day-$nextDay',
                tag: 'DayEventsScreen',
                error: error,
                stackTrace: stackTrace,
              );
              return const Center(child: Text('予定を読み込めませんでした。通信環境を確認してください。'));
            },
            data: (events) {
              if (events.isEmpty) {
                return const _EmptyState();
              }
              final orderedEvents = orderEventsForDisplay(events, currentUid);
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: orderedEvents.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final event = orderedEvents[index];
                  return _EventTile(event: event, membersById: membersById);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 日別画面内で前後の日へ移動する操作を提供する（Issue #53 / NFR-1）。
class _DayNavigationHeader extends StatelessWidget {
  const _DayNavigationHeader({
    required this.day,
    required this.onPreviousDay,
    required this.onNextDay,
  });

  final DateTime day;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '前日の予定へ',
            onPressed: onPreviousDay,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${_formatDate(day)} の予定',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: '翌日の予定へ',
            onPressed: onNextDay,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.membersById});

  final Event event;
  final Map<String, User> membersById;

  @override
  Widget build(BuildContext context) {
    final memberColors = event.memberIds
        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
        .toList();
    final participantsLabel = _participantsLabel(event);
    final memoPreview = event.memo.trim();
    return ListTile(
      leading: _MemberDots(colors: memberColors),
      title: _TitleLine(
        title: event.title,
        participantsLabel: participantsLabel,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              _scheduleLabel(event),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (memoPreview.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'メモ: $memoPreview',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: EventTypeBadge(event.type),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.eventEdit,
        arguments: EventEditArgs.edit(event),
      ),
    );
  }

  /// 参加者名を「・」区切りで返す（FR-2、Issue #53）。
  ///
  /// 色だけでは誰の予定か判別しにくいため、1人予定でも名前を表示する。
  String? _participantsLabel(Event event) {
    final ids = event.memberIds;
    final names = ids
        .map((id) => membersById[id]?.name.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    return names.join('・');
  }

  String _scheduleLabel(Event event) {
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    final sameDay = _isSameDate(start, end);

    if (event.allDay) {
      if (sameDay) {
        return '終日';
      }
      return '${_formatMonthDay(start)}〜${_formatMonthDay(end)}・終日';
    }
    if (!sameDay) {
      return '${_formatMonthDay(start)} ${_formatTime(start)}'
          '〜${_formatMonthDay(end)} ${_formatTime(end)}';
    }
    return '${_two(start.hour)}:${_two(start.minute)}'
        '〜${_two(end.hour)}:${_two(end.minute)}';
  }

  bool _isSameDate(DateTime start, DateTime end) =>
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;

  String _formatMonthDay(DateTime dateTime) =>
      '${dateTime.month}/${dateTime.day}';

  String _formatTime(DateTime dateTime) =>
      '${_two(dateTime.hour)}:${_two(dateTime.minute)}';
}

class _TitleLine extends StatelessWidget {
  const _TitleLine({required this.title, required this.participantsLabel});

  final String title;
  final String? participantsLabel;

  @override
  Widget build(BuildContext context) {
    final label = participantsLabel;
    return Row(
      children: [
        Flexible(
          flex: 3,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (label != null) ...[
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              '参加: $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 参加メンバーを色付きドットで並べる（FR-2、参加者の可視化）。
///
/// 一目で誰が参加しているか把握できるよう、単色に頼らず全員分表示する。
class _MemberDots extends StatelessWidget {
  const _MemberDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (final color in colors)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available,
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 8),
          const Text('予定はありません'),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _formatDate(DateTime day) =>
    '${day.year}/${_two(day.month)}/${_two(day.day)}';

DateTime _addCalendarDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

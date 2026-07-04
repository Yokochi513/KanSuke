import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/routes.dart';
import '../../../core/color_utils.dart';
import '../../../models/models.dart';
import '../../events/application/event_providers.dart';
import '../../users/application/user_providers.dart';

/// カレンダー月表示（FR-4）。
///
/// 各日にメンバー色のドットを表示し、仮＝点線枠・半透明／確定＝塗りつぶしで
/// 種別を区別する（FR-2 / FR-3、基本設計 §6.1・§6.3）。表示は
/// [eventsInRangeProvider] のスナップショット（ローカルキャッシュ起点）に従う（NFR-1）。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// 表示中の月の範囲 `[月初, 翌月初)`。月切替時のみ差し替わる（差分取得）。
  DateRange get _monthRange => (
    start: DateTime(_focusedDay.year, _focusedDay.month, 1),
    end: DateTime(_focusedDay.year, _focusedDay.month + 1, 1),
  );

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsInRangeProvider(_monthRange));
    final membersById = ref.watch(membersByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('カレンダー'),
        actions: [
          IconButton(
            tooltip: '設定',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCalendar(eventsAsync.asData?.value ?? const [], membersById),
          const Divider(height: 1),
          const _MemberLegend(),
          Expanded(
            child: eventsAsync.when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('予定を読み込めませんでした。通信環境を確認してください。')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(List<Event> events, Map<String, User> membersById) {
    final byDay = _groupByDay(events);

    return TableCalendar<Event>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: '月'},
      startingDayOfWeek: StartingDayOfWeek.sunday,
      calendarStyle: const CalendarStyle(outsideDaysVisible: false),
      eventLoader: (day) => byDay[_dateKey(day)] ?? const [],
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = focusedDay);
      },
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        // FR-4: 日付タップで日別一覧へ遷移する（対象日を引数で渡す）。
        Navigator.pushNamed(
          context,
          AppRoutes.dayEvents,
          arguments: DateUtils.dateOnly(selectedDay),
        );
      },
      calendarBuilders: CalendarBuilders<Event>(
        markerBuilder: (context, day, dayEvents) {
          if (dayEvents.isEmpty) {
            return null;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final event in dayEvents.take(4))
                  EventDot(
                    color: colorFromHex(
                      membersById[event.ownerId]?.color ?? '',
                    ),
                    type: event.type,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<DateTime, List<Event>> _groupByDay(List<Event> events) {
    final map = <DateTime, List<Event>>{};
    for (final event in events) {
      final key = _dateKey(event.startAt.toLocal());
      map.putIfAbsent(key, () => []).add(event);
    }
    return map;
  }

  DateTime _dateKey(DateTime day) => DateTime(day.year, day.month, day.day);
}

/// メンバー色・種別を表す小さなドット。
///
/// 確定＝塗りつぶし、仮＝点線枠・半透明（FR-3、基本設計 §6.3）。
class EventDot extends StatelessWidget {
  const EventDot({required this.color, required this.type, super.key});

  final Color color;
  final EventType type;

  @override
  Widget build(BuildContext context) {
    final confirmed = type == EventType.confirmed;
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: confirmed ? color : color.withValues(alpha: 0.28),
        border: confirmed ? null : Border.all(color: color, width: 1),
      ),
    );
  }
}

/// メンバー色の凡例（FR-2、基本設計 §6.3）。
class _MemberLegend extends ConsumerWidget {
  const _MemberLegend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(familyMembersProvider).asData?.value ?? const [];
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final member in members)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorFromHex(member.color),
                  ),
                ),
                const SizedBox(width: 4),
                Text(member.name),
              ],
            ),
        ],
      ),
    );
  }
}

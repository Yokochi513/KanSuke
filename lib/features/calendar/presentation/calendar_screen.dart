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
/// 各日をマス目（枠線付きセル）で描画し、予定を所有者色のバー＋タイトルで
/// 表示する。仮＝点線枠・半透明／確定＝塗りつぶしで種別を区別する
/// （FR-2 / FR-3、基本設計 §6.1・§6.3）。マス目形式にすることで、複数人の
/// 予定が同じ日に入っても一目で誰の予定かを判別できる。表示は
/// [eventsInRangeProvider] のスナップショット（ローカルキャッシュ起点）に従う（NFR-1）。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// 曜日ヘッダの高さ。行の高さ計算に使う。
  static const double _daysOfWeekHeight = 22;

  /// グリッドの行数。常に 6 週で固定し（sixWeekMonthsEnforced）、月による
  /// 高さのばらつきをなくす。行の高さ計算に使う。
  static const int _weekRows = 6;

  /// 表示中の月の範囲 `[月初, 翌月初)`。月切替時のみ差し替わる（差分取得）。
  DateRange get _monthRange => (
    start: DateTime(_focusedDay.year, _focusedDay.month, 1),
    end: DateTime(_focusedDay.year, _focusedDay.month + 1, 1),
  );

  void _changeMonth(int delta) {
    setState(
      () => _focusedDay = DateTime(
        _focusedDay.year,
        _focusedDay.month + delta,
        1,
      ),
    );
  }

  void _goToToday() {
    setState(() => _focusedDay = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsInRangeProvider(_monthRange));
    final membersById = ref.watch(membersByIdProvider);
    final events = eventsAsync.asData?.value ?? const <Event>[];

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
          if (eventsAsync.isLoading && !eventsAsync.hasValue)
            const LinearProgressIndicator(minHeight: 2),
          if (eventsAsync.hasError)
            const _ErrorBanner('予定を読み込めませんでした。通信環境を確認してください。'),
          // 月ナビゲーションは固定高で Expanded の外に置き、行高計算を単純にする。
          _MonthHeader(
            focusedDay: _focusedDay,
            onPrev: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
            onToday: _goToToday,
          ),
          // カレンダーは残りの高さいっぱいに広げ、各マスを大きく取る。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 常に 6 週グリッドで描画する（sixWeekMonthsEnforced）ので、
                // 曜日行を除いた残りを 6 で割れば行高が決まる。切り捨てにより
                // 6×行高 ≤ 残り高となりオーバーフローしない。
                final available = constraints.maxHeight - _daysOfWeekHeight;
                final rowHeight = (available / _weekRows).floorToDouble().clamp(
                  52.0,
                  240.0,
                );
                return _buildCalendar(events, membersById, rowHeight);
              },
            ),
          ),
          const Divider(height: 1),
          const _MemberLegend(),
        ],
      ),
    );
  }

  Widget _buildCalendar(
    List<Event> events,
    Map<String, User> membersById,
    double rowHeight,
  ) {
    final byDay = _groupByDay(events);

    Widget cellBuilder(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      bool isOutside = false,
    }) {
      return _DayCell(
        day: day,
        events: byDay[_dateKey(day)] ?? const [],
        membersById: membersById,
        rowHeight: rowHeight,
        isToday: isToday,
        isSelected: isSelected,
        isOutside: isOutside,
      );
    }

    return TableCalendar<Event>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _focusedDay,
      rowHeight: rowHeight,
      daysOfWeekHeight: _daysOfWeekHeight,
      // 月ナビゲーションは自前ヘッダで描画するため内蔵ヘッダは非表示にする。
      headerVisible: false,
      // 常に 6 週で描画し、行高計算と実描画の週数を一致させる。
      sixWeekMonthsEnforced: true,
      // Expanded で与えた高さぴったりにマスを敷き詰める（行高は内部で算出）。
      shouldFillViewport: true,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: '月'},
      startingDayOfWeek: StartingDayOfWeek.sunday,
      // マス目を隙間なく敷き詰め、隣接する枠線でグリッドを形成する。
      calendarStyle: const CalendarStyle(
        cellMargin: EdgeInsets.zero,
        cellPadding: EdgeInsets.zero,
        outsideDaysVisible: true,
      ),
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
        defaultBuilder: (context, day, _) => cellBuilder(day),
        todayBuilder: (context, day, _) => cellBuilder(day, isToday: true),
        selectedBuilder: (context, day, _) =>
            cellBuilder(day, isSelected: true),
        outsideBuilder: (context, day, _) => cellBuilder(day, isOutside: true),
      ),
    );
  }

  Map<DateTime, List<Event>> _groupByDay(List<Event> events) {
    final map = <DateTime, List<Event>>{};
    for (final event in events) {
      final key = _dateKey(event.startAt.toLocal());
      map.putIfAbsent(key, () => []).add(event);
    }
    // 表示順を安定させる：終日を先頭、次に開始時刻順。
    for (final list in map.values) {
      list.sort((a, b) {
        if (a.allDay != b.allDay) {
          return a.allDay ? -1 : 1;
        }
        return a.startAt.compareTo(b.startAt);
      });
    }
    return map;
  }

  DateTime _dateKey(DateTime day) => DateTime(day.year, day.month, day.day);
}

/// カレンダーの 1 マス（1 日分のセル）。
///
/// 枠線でグリッドを形成し、日付とその日の予定バーを縦に並べる。マスに
/// 収まらない分は「+N」で省略表示する（FR-4）。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.events,
    required this.membersById,
    required this.rowHeight,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
  });

  final DateTime day;
  final List<Event> events;
  final Map<String, User> membersById;
  final double rowHeight;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;

  static const double _headerHeight = 22;
  static const double _barSlot = 18; // バー高さ + 下マージン

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // マスの高さから、表示できるバー本数を見積もる。
    final available = rowHeight - _headerHeight - 2;
    final capacity = available <= 0 ? 0 : (available ~/ _barSlot);

    final List<Event> visible;
    final int hidden;
    if (events.length <= capacity) {
      visible = events;
      hidden = 0;
    } else {
      // 「+N」の 1 行分を確保するため、表示本数を 1 つ減らす。
      final show = (capacity - 1).clamp(0, events.length);
      visible = events.take(show).toList();
      hidden = events.length - show;
    }

    final border = BorderSide(color: scheme.outlineVariant, width: 0.5);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected
            ? scheme.primary.withValues(alpha: 0.08)
            : (isToday ? scheme.primary.withValues(alpha: 0.04) : null),
        border: isSelected
            ? Border.all(color: scheme.primary, width: 1)
            : Border(top: border, left: border, right: border, bottom: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dayLabel(scheme),
            for (final event in visible)
              EventBar(
                title: event.title,
                color: colorFromHex(membersById[event.ownerId]?.color ?? ''),
                type: event.type,
              ),
            if (hidden > 0)
              Text(
                '+$hidden',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayLabel(ColorScheme scheme) {
    final Color numberColor;
    if (isOutside) {
      numberColor = scheme.onSurface.withValues(alpha: 0.35);
    } else if (day.weekday == DateTime.sunday) {
      numberColor = Colors.red.shade400;
    } else if (day.weekday == DateTime.saturday) {
      numberColor = Colors.blue.shade400;
    } else {
      numberColor = scheme.onSurface;
    }

    return SizedBox(
      height: _headerHeight,
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          width: 20,
          height: 18,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
              : null,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isToday ? scheme.onPrimary : numberColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// 予定を表す 1 本のバー（FR-2 / FR-3、基本設計 §6.3）。
///
/// 所有者色で塗り、確定＝塗りつぶし、仮＝枠線・半透明で種別を区別する。
/// 幅は親（マスの縦積み）に合わせて広がる。
class EventBar extends StatelessWidget {
  const EventBar({
    required this.title,
    required this.color,
    required this.type,
    super.key,
  });

  final String title;
  final Color color;
  final EventType type;

  @override
  Widget build(BuildContext context) {
    final confirmed = type == EventType.confirmed;
    final textColor = confirmed
        ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black)
        : color;

    return Container(
      height: 16,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: confirmed ? color : color.withValues(alpha: 0.16),
        border: confirmed ? null : Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.0,
          fontWeight: confirmed ? FontWeight.w600 : FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

/// 月ナビゲーションヘッダ（前月・当月タイトル・翌月・今日）。
///
/// TableCalendar 内蔵ヘッダの代わりに固定高で描画し、カレンダー本体の
/// 行高計算を単純化する。
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.focusedDay,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime focusedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: '前の月',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${focusedDay.year}年${focusedDay.month}月',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          TextButton(onPressed: onToday, child: const Text('今日')),
          IconButton(
            tooltip: '次の月',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// 予定の読み込み失敗時に表示する軽量バナー。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
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

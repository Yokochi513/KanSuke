import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/routes.dart';
import '../../../core/color_utils.dart';
import '../../../core/japanese_holidays.dart';
import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../events/application/event_ordering.dart';
import '../../events/application/event_providers.dart';
import '../../users/application/user_providers.dart';

/// カレンダー月表示（FR-4）。
///
/// 各日をマス目（枠線付きセル）で描画し、予定を参加者の色のバー＋タイトルで
/// 表示する。仮＝点線枠・半透明／確定＝塗りつぶしで種別を区別する
/// （FR-2 / FR-3、基本設計 §6.1・§6.3）。マス目形式にすることで、複数人の
/// 予定が同じ日に入っても一目で誰の予定かを判別できる。表示は
/// [eventsInRangeProvider] のスナップショット（ローカルキャッシュ起点）に従う（NFR-1）。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.initialFocusedDay});

  final DateTime? initialFocusedDay;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  /// 曜日ヘッダの高さ。行の高さ計算に使う。
  static const double _daysOfWeekHeight = 22;

  /// グリッドの行数。常に 6 週で固定し（sixWeekMonthsEnforced）、月による
  /// 高さのばらつきをなくす。行の高さ計算に使う。
  static const int _weekRows = 6;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialFocusedDay ?? DateTime.now();
  }

  /// 画面に実際に見えている 6 週グリッドの範囲 `[先頭日, 最終日の翌日)`。
  ///
  /// Issue #59 / FR-4: 前後月の日付セルも表示しているため、そのセルの予定も
  /// 読み込む。当月だけではなく 42 日分に限定して取得し、月切替の軽さを保つ。
  DateRange get _visibleCalendarRange {
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final firstVisibleDay = monthStart.subtract(
      Duration(days: monthStart.weekday % 7),
    );
    return (
      start: firstVisibleDay,
      end: firstVisibleDay.add(const Duration(days: _weekRows * 7)),
    );
  }

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

  /// ヘッダの「YYYY年MM月」タップで年月一覧を出し、選択した月へ飛ぶ（Issue #32）。
  Future<void> _openMonthYearPicker() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MonthYearPickerSheet(focusedDay: _focusedDay),
    );
    if (picked != null) {
      setState(() => _focusedDay = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRange = _visibleCalendarRange;
    final eventsAsync = ref.watch(eventsInRangeProvider(visibleRange));
    final membersById = ref.watch(membersByIdProvider);
    final currentUid = ref.watch(currentUidProvider);
    final events = eventsAsync.asData?.value ?? const <Event>[];
    if (eventsAsync.hasError) {
      AppLogger.error(
        'eventsInRangeProvider errored for $visibleRange',
        tag: 'CalendarScreen',
        error: eventsAsync.error,
        stackTrace: eventsAsync.stackTrace,
      );
    }

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
            onTapTitle: _openMonthYearPicker,
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
                return _buildCalendar(
                  events,
                  membersById,
                  rowHeight,
                  currentUid,
                );
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
    String? currentUid,
  ) {
    final byDay = _groupByDay(
      events,
      range: _visibleCalendarRange,
      currentUid: currentUid,
    );

    Widget cellBuilder(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      bool isOutside = false,
    }) {
      return _DayCell(
        day: day,
        segments: byDay[_dateKey(day)] ?? const [],
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
      // 1 回目タップ＝日の選択（ハイライト）、選択済みの日を再タップ＝日別一覧へ遷移。
      // Issue #45 / FR-4: ダブルタップの短い時間制限に依存せず、選択日への
      // 明示的な 2 回目タップで日別一覧へ移動できるようにする。
      onDaySelected: (selectedDay, focusedDay) {
        final selectedDayAlreadyFocused = isSameDay(_selectedDay, selectedDay);

        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });

        if (selectedDayAlreadyFocused) {
          // FR-4: 対象日を引数で渡して日別一覧へ遷移する。
          Navigator.pushNamed(
            context,
            AppRoutes.dayEvents,
            arguments: DateUtils.dateOnly(selectedDay),
          );
        }
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

  /// 日付ごとの表示レーン割り当てを求める（Issue #56）。
  ///
  /// 複数日にまたがる予定は、日〜土の週単位で同じレーン（縦位置）を
  /// 保つように割り当てる。これにより [_DayCell] は日をまたいでも
  /// 同じ高さにバーを描画でき、実際の開始・終了日以外は角丸/枠線を
  /// 外すことで隣接する日のマスと連結して見えるようになる。
  Map<DateTime, List<_EventSegment?>> _groupByDay(
    List<Event> events, {
    required DateRange range,
    required String? currentUid,
  }) {
    final firstVisibleDay = _dateKey(range.start);
    final lastVisibleDay = _dateKey(
      range.end,
    ).subtract(const Duration(days: 1));

    // イベントごとに表示範囲でクリップした開始・終了日を求める。
    final clippedRanges = <Event, ({DateTime start, DateTime end})>{};
    for (final event in events) {
      final eventStartDay = _dateKey(event.startAt.toLocal());
      final eventEndDay = _dateKey(event.endAt.toLocal());
      final start = eventStartDay.isBefore(firstVisibleDay)
          ? firstVisibleDay
          : eventStartDay;
      final end = eventEndDay.isAfter(lastVisibleDay)
          ? lastVisibleDay
          : eventEndDay;
      // FR-4: 既存の終日単日予定（startAt == endAt）を保つため終了日も含める。
      if (end.isBefore(start)) continue;
      clippedRanges[event] = (start: start, end: end);
    }

    DateTime weekStart(DateTime day) =>
        day.subtract(Duration(days: day.weekday % 7));

    // 週（日曜始まり）ごとに、その週に登場する予定を集める。
    final eventsByWeek = <DateTime, List<Event>>{};
    for (final entry in clippedRanges.entries) {
      var week = weekStart(entry.value.start);
      final lastWeek = weekStart(entry.value.end);
      while (!week.isAfter(lastWeek)) {
        eventsByWeek.putIfAbsent(week, () => []).add(entry.key);
        week = week.add(const Duration(days: 7));
      }
    }

    // 週内で区間グラフの貪欲彩色を行い、重ならない予定同士でレーンを
    // 使い回す。開始日が早い順、次いで表示優先度順に詰めることで、
    // 同日に複数の予定がある場合の見た目の順序も既存挙動を保つ。
    final laneByEventPerWeek = <DateTime, Map<Event, int>>{};
    for (final weekEntry in eventsByWeek.entries) {
      final week = weekEntry.key;
      final weekEnd = week.add(const Duration(days: 6));
      final weekEvents = weekEntry.value.toList()
        ..sort((a, b) {
          final aStart = clippedRanges[a]!.start.isBefore(week)
              ? week
              : clippedRanges[a]!.start;
          final bStart = clippedRanges[b]!.start.isBefore(week)
              ? week
              : clippedRanges[b]!.start;
          final byStart = aStart.compareTo(bStart);
          if (byStart != 0) return byStart;
          return compareEventsForDisplay(a, b, currentUid);
        });

      final laneEndDay = <int, DateTime>{};
      final lanes = <Event, int>{};
      for (final event in weekEvents) {
        final range = clippedRanges[event]!;
        final start = range.start.isBefore(week) ? week : range.start;
        final end = range.end.isAfter(weekEnd) ? weekEnd : range.end;
        var lane = 0;
        while (laneEndDay[lane] != null && !laneEndDay[lane]!.isBefore(start)) {
          lane++;
        }
        laneEndDay[lane] = end;
        lanes[event] = lane;
      }
      laneByEventPerWeek[week] = lanes;
    }

    final map = <DateTime, List<_EventSegment?>>{};
    for (final entry in clippedRanges.entries) {
      final event = entry.key;
      final range = entry.value;
      for (
        var day = range.start;
        !day.isAfter(range.end);
        day = day.add(const Duration(days: 1))
      ) {
        final lane = laneByEventPerWeek[weekStart(day)]![event]!;
        final slots = map.putIfAbsent(day, () => []);
        while (slots.length <= lane) {
          slots.add(null);
        }
        slots[lane] = _EventSegment(
          event: event,
          roundLeft:
              day.isAtSameMomentAs(range.start) ||
              day.weekday == DateTime.sunday,
          roundRight:
              day.isAtSameMomentAs(range.end) ||
              day.weekday == DateTime.saturday,
        );
      }
    }
    return map;
  }

  DateTime _dateKey(DateTime day) => DateTime(day.year, day.month, day.day);
}

/// ある日のマスに描画する予定 1 件分の情報（Issue #56）。
///
/// [roundLeft] / [roundRight] は、その日が予定の実際の開始・終了日
/// （または週の先頭・末尾で行が折り返す境界）かどうかを表す。false の
/// 場合は角丸・枠線を外し、隣接する日のバーと連結して見えるようにする。
class _EventSegment {
  const _EventSegment({
    required this.event,
    required this.roundLeft,
    required this.roundRight,
  });

  final Event event;
  final bool roundLeft;
  final bool roundRight;
}

/// カレンダーの 1 マス（1 日分のセル）。
///
/// 枠線でグリッドを形成し、日付とその日の予定バーを縦に並べる。マスに
/// 収まらない分は「+N」で省略表示する（FR-4）。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.segments,
    required this.membersById,
    required this.rowHeight,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
  });

  final DateTime day;
  final List<_EventSegment?> segments;
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
    final holidayName = isOutside ? null : japaneseHolidayName(day);

    // マスの高さから、表示できるバー本数を見積もる。
    final available = rowHeight - _headerHeight - 2;
    final capacity = available <= 0 ? 0 : (available ~/ _barSlot);

    final List<_EventSegment?> visible;
    final int hidden;
    if (segments.length <= capacity) {
      visible = segments;
      hidden = 0;
    } else {
      // 「+N」の 1 行分を確保するため、表示本数を 1 つ減らす。
      final show = (capacity - 1).clamp(0, segments.length);
      visible = segments.take(show).toList();
      hidden = segments.skip(show).whereType<_EventSegment>().length;
    }

    final border = BorderSide(color: scheme.outlineVariant, width: 0.5);
    final Color? backgroundColor;
    if (isSelected) {
      backgroundColor = scheme.primary.withValues(alpha: 0.08);
    } else if (isToday) {
      backgroundColor = scheme.primary.withValues(alpha: 0.04);
    } else {
      backgroundColor = null;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isSelected
            ? Border.all(color: scheme.primary, width: 1)
            : Border(top: border, left: border, right: border, bottom: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FR-4: 祝日は日付色とチップで強調し、月表示で見落としにくくする。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _dayLabel(scheme, holidayName),
            ),
            for (final segment in visible)
              if (segment == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: SizedBox(height: 16),
                )
              else
                Padding(
                  // Issue #56: 実際の開始・終了日以外は左右の余白を詰め、
                  // 隣接する日のバーと隙間なく連結して見えるようにする。
                  padding: EdgeInsets.only(
                    left: segment.roundLeft ? 2 : 0,
                    right: segment.roundRight ? 2 : 0,
                  ),
                  child: EventBar(
                    title: segment.event.title,
                    colors: segment.event.memberIds
                        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
                        .toList(),
                    type: segment.event.type,
                    roundLeft: segment.roundLeft,
                    roundRight: segment.roundRight,
                    // Issue #56: 複数日にまたがる予定は、週内で最初に現れる日
                    // （roundLeft、実際の開始日または週の折り返し先頭）にのみ
                    // タイトルを出す。毎日同じ名前が並ぶと煩わしいため。
                    showTitle: segment.roundLeft,
                  ),
                ),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '+$hidden',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayLabel(ColorScheme scheme, String? holidayName) {
    final isHoliday = holidayName != null;
    final Color numberColor;
    if (isOutside) {
      numberColor = scheme.onSurface.withValues(alpha: 0.35);
    } else if (isHoliday || day.weekday == DateTime.sunday) {
      numberColor = Colors.red.shade400;
    } else if (day.weekday == DateTime.saturday) {
      numberColor = Colors.blue.shade400;
    } else {
      numberColor = scheme.onSurface;
    }

    return SizedBox(
      height: _headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 18,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(
                    color: isHoliday ? scheme.error : scheme.primary,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isToday
                    ? (isHoliday ? scheme.onError : scheme.onPrimary)
                    : numberColor,
              ),
            ),
          ),
          if (holidayName != null)
            Expanded(child: _HolidayLabel(name: holidayName)),
        ],
      ),
    );
  }
}

/// 祝日名ラベル（例: 「海の日」）。"祝" という記号だけでは何の祝日か
/// わからないため、名称そのものを表示して一目で判別できるようにする。
class _HolidayLabel extends StatelessWidget {
  const _HolidayLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 3),
      child: Tooltip(
        message: name,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Colors.red.shade400,
          ),
        ),
      ),
    );
  }
}

/// 予定を表す 1 本のバー（FR-2 / FR-3、基本設計 §6.3）。
///
/// 参加メンバーの色で等分割して塗り、確定＝塗りつぶし・
/// 仮＝枠線＋半透明で種別を区別する。参加者が 1 人ならこれまで通り単色になる。
/// 幅は親（マスの縦積み）に合わせて広がる。
///
/// [roundLeft] / [roundRight] は、複数日にまたがる予定（Issue #56）で
/// 実際の開始・終了日以外の角丸/枠線を外すために使う。これにより隣接
/// する日のマスに描かれた同じ予定のバーと視覚的につながって見える。
///
/// [showTitle] を false にするとタイトルを描画しない。複数日にまたがる
/// 予定は毎日同じ名前が並ぶと煩わしいため、週内で最初に現れる日にのみ
/// 表示する運用にしている（呼び出し側で制御）。
class EventBar extends StatelessWidget {
  const EventBar({
    required this.title,
    required this.colors,
    required this.type,
    this.roundLeft = true,
    this.roundRight = true,
    this.showTitle = true,
    super.key,
  });

  final String title;
  final List<Color> colors;
  final EventType type;
  final bool roundLeft;
  final bool roundRight;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final confirmed = type == EventType.confirmed;
    final primary = colors.first;
    final textColor = confirmed
        ? (ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
              ? Colors.white
              : Colors.black)
        : primary;
    const radius = Radius.circular(3);

    return Container(
      height: 16,
      margin: const EdgeInsets.only(bottom: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: confirmed
            ? null
            : Border(
                top: BorderSide(color: primary, width: 1),
                bottom: BorderSide(color: primary, width: 1),
                left: roundLeft
                    ? BorderSide(color: primary, width: 1)
                    : BorderSide.none,
                right: roundRight
                    ? BorderSide(color: primary, width: 1)
                    : BorderSide.none,
              ),
        borderRadius: BorderRadius.only(
          topLeft: roundLeft ? radius : Radius.zero,
          bottomLeft: roundLeft ? radius : Radius.zero,
          topRight: roundRight ? radius : Radius.zero,
          bottomRight: roundRight ? radius : Radius.zero,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            // Row+Expanded の等分割は Flutter 3.41.6 でこの構成だと塗りが
            // 描画されないため、LayoutBuilder で幅を計算し固定幅の
            // SizedBox で等分割している（flex レイアウトを使わない）。
            child: LayoutBuilder(
              builder: (context, constraints) {
                final segmentWidth = constraints.maxWidth / colors.length;
                return Row(
                  children: [
                    for (final color in colors)
                      SizedBox(
                        width: segmentWidth,
                        height: constraints.maxHeight,
                        child: ColoredBox(
                          color: confirmed
                              ? color
                              : color.withValues(alpha: 0.16),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (showTitle)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.centerLeft,
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
              ),
            ),
        ],
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
    required this.onTapTitle,
  });

  final DateTime focusedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onTapTitle;

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
              // Issue #32: タップで年月一覧を出し、選択した月へ直接飛べるようにする。
              child: InkWell(
                onTap: onTapTitle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    '${focusedDay.year}年${focusedDay.month}月',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
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

/// 年月を選ぶボトムシート（Issue #32）。
///
/// 「年」「月」それぞれをスクロールホイール（[CupertinoPicker]）で選ばせる、
/// iOS の日付選択に準じた見た目にする。ホイールは慣性でスクロールが止まる
/// まで値が確定しないため、「完了」で明示的に選択を確定する。
class _MonthYearPickerSheet extends StatefulWidget {
  const _MonthYearPickerSheet({required this.focusedDay});

  final DateTime focusedDay;

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  // TableCalendar の firstDay/lastDay（calendar_screen.dart 内）と範囲を揃える。
  static const int _minYear = 2020;
  static const int _maxYear = 2035;
  static const double _itemExtent = 40;

  late int _year;
  late int _month;

  // build() のたびに作り直すと、一方のホイールを操作した setState が
  // もう一方のコントローラも作り直してしまい、進行中のドラッグ操作を
  // 中断させて互いに干渉して見える。State のフィールドとして一度だけ
  // 生成し、以後は使い回すことで年・月を独立して操作できるようにする。
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;

  @override
  void initState() {
    super.initState();
    _year = widget.focusedDay.year;
    _month = widget.focusedDay.month;
    _yearController = FixedExtentScrollController(
      initialItem: _year - _minYear,
    );
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, DateTime(_year, _month, 1)),
                  child: const Text('完了'),
                ),
              ],
            ),
            SizedBox(
              height: 180,
              // 既定の ScrollBehavior はマウスでのドラッグ操作を許可しない
              // （マウスホイールでの回転のみ）ため、クリックしたまま上下に
              // 流す操作もできるよう明示的に許可する。
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: _yearController,
                        itemExtent: _itemExtent,
                        onSelectedItemChanged: (index) =>
                            setState(() => _year = _minYear + index),
                        selectionOverlay: _PickerSelectionOverlay(
                          color: scheme.primary,
                        ),
                        children: [
                          for (var year = _minYear; year <= _maxYear; year++)
                            Center(child: Text('$year年')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: _monthController,
                        itemExtent: _itemExtent,
                        onSelectedItemChanged: (index) =>
                            setState(() => _month = index + 1),
                        selectionOverlay: _PickerSelectionOverlay(
                          color: scheme.primary,
                        ),
                        children: [
                          for (var month = 1; month <= 12; month++)
                            Center(child: Text('$month月')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ホイールの選択中央行を示す帯。既定の [CupertinoPickerDefaultSelectionOverlay]
/// はテーマの primary 色と馴染まないため、テーマ色の帯に差し替える。
class _PickerSelectionOverlay extends StatelessWidget {
  const _PickerSelectionOverlay({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
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

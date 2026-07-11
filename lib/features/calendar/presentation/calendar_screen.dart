import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/color_utils.dart';
import '../../../core/japanese_holidays.dart';
import '../../../core/logger.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
import '../../calendars/presentation/calendar_switcher.dart';
import '../../events/application/event_grouping.dart';
import '../../events/application/event_ordering.dart';
import '../../events/application/event_providers.dart';
import '../../events/presentation/event_edit_args.dart';
import '../../events/presentation/event_type_badge.dart';
import '../../settings/application/event_merge_provider.dart';
import '../../users/application/user_providers.dart';

/// カレンダー月表示（FR-4）。
///
/// 各日をマス目（枠線付きセル）で描画し、予定を参加者の色のバー＋タイトルで
/// 表示する。仮＝点線枠・半透明／確定＝塗りつぶしで種別を区別する
/// （FR-2 / FR-3、基本設計 §6.1・§6.3）。マス目形式にすることで、複数人の
/// 予定が同じ日に入っても一目で誰の予定かを判別できる。表示は
/// [eventsInRangeProvider] のスナップショット（ローカルキャッシュ起点）に従う（NFR-1）。
///
/// Issue #72: 複数日にまたがる予定は、マスの上に重ねた 1 本の連続バー
/// （[_EventBarsOverlay]）として週の該当マス幅いっぱいに描画する。これにより
/// 題名を全幅で表示でき、参加者の色分けも 1 日単位で分断されず span 全体で
/// 1 回だけ見えるようになる。グリッド（マス目・日付・祝日・タップ判定）は
/// [TableCalendar] が担い、バーはその上に絶対座標で載せる。TableCalendar は
/// 6 週固定（sixWeekMonthsEnforced）かつ高さいっぱい（shouldFillViewport）で
/// 描くため、行高 =（利用可能高 − 曜日ヘッダ高）/ 6、列幅 = 幅 / 7 と
/// 決定論的に定まり、オーバーレイと画素単位で一致させられる。
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

  /// マス内で日付番号（＋祝日名）が占める高さ。バーはこの下に載せる。
  /// [_DayCell] の上パディング（1）＋日付ラベル高（21）に合わせる。
  static const double _dayNumberHeight = 22;

  /// バー 1 本分の縦スロット（バー高 16 ＋下マージン 2）。
  static const double _barSlot = 18;

  /// バーの高さ。
  static const double _barHeight = 16;

  /// 横スワイプを月送りと判定する速度しきい値（論理px/秒）。
  static const double _swipeVelocityThreshold = 200;

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
    final calendarId = ref.watch(selectedCalendarIdProvider);
    final eventsAsync = ref.watch(
      eventsInRangeProvider((
        start: visibleRange.start,
        end: visibleRange.end,
        calendarId: calendarId,
      )),
    );
    final membersById = ref.watch(membersByIdProvider);
    final currentUid = ref.watch(currentUidProvider);
    final mergeEnabled = ref.watch(resolvedEventMergeEnabledProvider);
    final events = eventsAsync.asData?.value ?? const <Event>[];
    if (eventsAsync.hasError) {
      AppLogger.error(
        'eventsInRangeProvider errored for $visibleRange/$calendarId',
        tag: 'CalendarScreen',
        error: eventsAsync.error,
        stackTrace: eventsAsync.stackTrace,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const CalendarSwitcherTitle(),
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
                // TableCalendar は高さいっぱい（shouldFillViewport）かつ 6 週固定で
                // 描くため、実際の行高＝（利用可能高 − 曜日ヘッダ高）/ 6、列幅＝
                // 幅 / 7 と決まる。オーバーレイもこの値で座標を合わせる。
                final rowHeight =
                    (constraints.maxHeight - _daysOfWeekHeight) / _weekRows;
                final colWidth = constraints.maxWidth / 7;
                // Issue #76: マージ ON なら同名・期間が連なる予定を 1 グループに
                // 束ね、OFF なら従来どおり 1 予定 = 1 グループとして扱う。以降の
                // レーン配置・「+N」計算はグループ単位で行う。
                final groups = mergeEnabled
                    ? groupEventsForMerge(events)
                    : [
                        for (final event in events) EventGroup([event]),
                      ];
                final layout = _computeBarLayout(
                  groups,
                  range: _visibleCalendarRange,
                  currentUid: currentUid,
                  rowHeight: rowHeight,
                );
                // Issue #72: TableCalendar 内蔵の横スワイプ（PageView）は
                // オーバーレイと同期しないため無効化し、代わりに横フリックを
                // 自前で拾って月送りする。月切替は setState による瞬時の
                // 差し替えとなり、グリッドとバーがずれない。
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -_swipeVelocityThreshold) {
                      _changeMonth(1);
                    } else if (velocity > _swipeVelocityThreshold) {
                      _changeMonth(-1);
                    }
                  },
                  child: Stack(
                    children: [
                      _buildCalendar(),
                      // バーはグリッドの上に載せる。普通のバー・「+N」は
                      // [IgnorePointer] でタップを下のマスへ通し、「日を選択→
                      // 再タップで日別一覧」の操作を保つ。束ねたバー（Issue #76）
                      // だけは自身でタップを受け、内訳シートを開く。
                      Positioned.fill(
                        child: _EventBarsOverlay(
                          bars: layout.bars,
                          markers: layout.markers,
                          membersById: membersById,
                          daysOfWeekHeight: _daysOfWeekHeight,
                          rowHeight: rowHeight,
                          colWidth: colWidth,
                          dayNumberHeight: _dayNumberHeight,
                          barSlot: _barSlot,
                          barHeight: _barHeight,
                        ),
                      ),
                    ],
                  ),
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

  Widget _buildCalendar() {
    Widget cellBuilder(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      bool isOutside = false,
    }) {
      return _DayCell(
        day: day,
        isToday: isToday,
        isSelected: isSelected,
        isOutside: isOutside,
      );
    }

    return TableCalendar<Event>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _focusedDay,
      daysOfWeekHeight: _daysOfWeekHeight,
      // 月ナビゲーションは自前ヘッダで描画するため内蔵ヘッダは非表示にする。
      headerVisible: false,
      // 常に 6 週で描画し、行高計算と実描画の週数を一致させる。
      sixWeekMonthsEnforced: true,
      // Expanded で与えた高さぴったりにマスを敷き詰める（行高は内部で算出）。
      shouldFillViewport: true,
      // Issue #72: 横スワイプ／ページ送りアニメーションはオーバーレイと
      // 同期しないため止める。月送りは自前の横フリックとヘッダのボタンで行う。
      availableGestures: AvailableGestures.none,
      pageAnimationEnabled: false,
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
        // 曜日ヘッダも日曜＝朱・土曜＝縹に揃え、マスの日付色と対応させる。
        dowBuilder: (context, day) => _DayOfWeekLabel(day: day),
        defaultBuilder: (context, day, _) => cellBuilder(day),
        todayBuilder: (context, day, _) => cellBuilder(day, isToday: true),
        selectedBuilder: (context, day, _) =>
            cellBuilder(day, isSelected: true),
        outsideBuilder: (context, day, _) => cellBuilder(day, isOutside: true),
      ),
    );
  }

  /// 表示中 6 週分の予定バー配置を計算する（Issue #56 / #72 / #76）。
  ///
  /// 複数日にまたがる予定は、日〜土の週単位で同じレーン（縦位置）を保つように
  /// 割り当て、週ごとに 1 本の連続バーとして描く。マスに収まらないレーンは
  /// 各日の「+N」に集約する。Issue #76: 束ねた予定グループは期間の和集合を
  /// 1 区間とし、1 レーンに畳む（「+N」計算でも 1 本と数える）。
  _BarLayout _computeBarLayout(
    List<EventGroup> groups, {
    required DateRange range,
    required String? currentUid,
    required double rowHeight,
  }) {
    final firstVisibleDay = _dateKey(range.start);
    final lastVisibleDay = _dateKey(
      range.end,
    ).subtract(const Duration(days: 1));

    // マスの高さから、表示できるバー本数を見積もる（[_DayCell] と同じ基準）。
    final available = rowHeight - _dayNumberHeight - 2;
    final capacity = available <= 0 ? 0 : (available ~/ _barSlot);

    // グループごとに表示範囲でクリップした開始・終了日（期間の和集合）を求める。
    final clippedRanges = <EventGroup, ({DateTime start, DateTime end})>{};
    for (final group in groups) {
      final groupStartDay = _dateKey(group.startAt.toLocal());
      final groupEndDay = _dateKey(group.endAt.toLocal());
      final start = groupStartDay.isBefore(firstVisibleDay)
          ? firstVisibleDay
          : groupStartDay;
      final end = groupEndDay.isAfter(lastVisibleDay)
          ? lastVisibleDay
          : groupEndDay;
      // FR-4: 既存の終日単日予定（startAt == endAt）を保つため終了日も含める。
      if (end.isBefore(start)) continue;
      clippedRanges[group] = (start: start, end: end);
    }

    DateTime weekStart(DateTime day) =>
        day.subtract(Duration(days: day.weekday % 7));

    // 週（日曜始まり）ごとに、その週に登場するグループを集める。
    final groupsByWeek = <DateTime, List<EventGroup>>{};
    for (final entry in clippedRanges.entries) {
      var week = weekStart(entry.value.start);
      final lastWeek = weekStart(entry.value.end);
      while (!week.isAfter(lastWeek)) {
        groupsByWeek.putIfAbsent(week, () => []).add(entry.key);
        week = week.add(const Duration(days: 7));
      }
    }

    final bars = <_BarSegment>[];
    final markers = <_OverflowMarker>[];

    for (final weekEntry in groupsByWeek.entries) {
      final week = weekEntry.key;
      final weekEnd = week.add(const Duration(days: 6));
      final weekIndex = week.difference(firstVisibleDay).inDays ~/ 7;

      // 週内で区間グラフの貪欲彩色を行い、重ならないグループ同士でレーンを
      // 使い回す。開始日が早い順、次いで表示優先度順に詰めることで、
      // 同日に複数の予定がある場合の見た目の順序も既存挙動を保つ。
      // グループの表示優先度は代表（先頭）予定で判定する。
      final weekGroups = weekEntry.value.toList()
        ..sort((a, b) {
          final aStart = clippedRanges[a]!.start.isBefore(week)
              ? week
              : clippedRanges[a]!.start;
          final bStart = clippedRanges[b]!.start.isBefore(week)
              ? week
              : clippedRanges[b]!.start;
          final byStart = aStart.compareTo(bStart);
          if (byStart != 0) return byStart;
          return compareEventsForDisplay(
            a.events.first,
            b.events.first,
            currentUid,
          );
        });

      final laneEndDay = <int, DateTime>{};
      final laneByGroup = <EventGroup, int>{};
      var laneCount = 0;
      for (final group in weekGroups) {
        final r = clippedRanges[group]!;
        final start = r.start.isBefore(week) ? week : r.start;
        final end = r.end.isAfter(weekEnd) ? weekEnd : r.end;
        var lane = 0;
        while (laneEndDay[lane] != null && !laneEndDay[lane]!.isBefore(start)) {
          lane++;
        }
        laneEndDay[lane] = end;
        laneByGroup[group] = lane;
        if (lane + 1 > laneCount) laneCount = lane + 1;
      }

      // 全レーンが収まらないときは、最後の 1 行を「+N」用に空ける。
      final maxVisibleLanes = laneCount <= capacity
          ? laneCount
          : (capacity - 1).clamp(0, laneCount);

      final hiddenPerCol = List<int>.filled(7, 0);
      for (final group in weekGroups) {
        final r = clippedRanges[group]!;
        final segStart = r.start.isBefore(week) ? week : r.start;
        final segEnd = r.end.isAfter(weekEnd) ? weekEnd : r.end;
        final startCol = segStart.weekday % 7;
        final endCol = segEnd.weekday % 7;
        final lane = laneByGroup[group]!;

        if (lane < maxVisibleLanes) {
          bars.add(
            _BarSegment(
              group: group,
              weekIndex: weekIndex,
              startCol: startCol,
              endCol: endCol,
              lane: lane,
              // 実際の開始・終了日にあたる端だけ角丸/枠線を付け、週をまたぐ
              // 継続端（週頭・週末）は角を落として次週へ連結して見せる。
              roundLeft: segStart.isAtSameMomentAs(r.start),
              roundRight: segEnd.isAtSameMomentAs(r.end),
              // 束ねたバーは日別ストリップ用に、この週スライスの各日で実際に
              // 参加しているメンバーを求める（Issue #76）。
              perDayMemberIds: group.isMerged
                  ? activeMemberIdsPerDay(group, segStart, segEnd)
                  : const [],
            ),
          );
        } else {
          for (var col = startCol; col <= endCol; col++) {
            hiddenPerCol[col]++;
          }
        }
      }

      for (var col = 0; col < 7; col++) {
        if (hiddenPerCol[col] > 0) {
          markers.add(
            _OverflowMarker(
              weekIndex: weekIndex,
              col: col,
              lane: maxVisibleLanes,
              count: hiddenPerCol[col],
            ),
          );
        }
      }
    }

    // (週, レーン, 開始列) 順に整え、描画順（＝レーンの優先順）を安定させる。
    bars.sort((a, b) {
      final byWeek = a.weekIndex.compareTo(b.weekIndex);
      if (byWeek != 0) return byWeek;
      final byLane = a.lane.compareTo(b.lane);
      if (byLane != 0) return byLane;
      return a.startCol.compareTo(b.startCol);
    });

    return _BarLayout(bars: bars, markers: markers);
  }

  DateTime _dateKey(DateTime day) => DateTime(day.year, day.month, day.day);
}

/// 週内 1 本分の予定バーの配置情報（Issue #72 / #76）。
///
/// [weekIndex] は表示中 6 週のうちの行（0〜5）、[startCol] / [endCol] は
/// その週での開始・終了列（0＝日曜〜6＝土曜）、[lane] は縦位置。
/// [roundLeft] / [roundRight] は、その端が予定の実際の開始・終了日
/// （＝週をまたぐ継続端ではない）かどうかを表す。[group] は 1 件のみなら
/// 普通の予定、2 件以上なら束ねた予定グループ（Issue #76）。
class _BarSegment {
  const _BarSegment({
    required this.group,
    required this.weekIndex,
    required this.startCol,
    required this.endCol,
    required this.lane,
    required this.roundLeft,
    required this.roundRight,
    this.perDayMemberIds = const [],
  });

  final EventGroup group;
  final int weekIndex;
  final int startCol;
  final int endCol;
  final int lane;
  final bool roundLeft;
  final bool roundRight;

  /// 束ねたバーの各日（この週スライスの [startCol]〜[endCol]）で実際に参加して
  /// いるメンバー ID。日別ストリップを描くために使う（Issue #76）。普通の予定は空。
  final List<List<String>> perDayMemberIds;
}

/// マスに収まらなかった予定を集約する「+N」マーカー（Issue #72）。
class _OverflowMarker {
  const _OverflowMarker({
    required this.weekIndex,
    required this.col,
    required this.lane,
    required this.count,
  });

  final int weekIndex;
  final int col;
  final int lane;
  final int count;
}

/// 予定バー配置の計算結果（Issue #72）。
class _BarLayout {
  const _BarLayout({required this.bars, required this.markers});

  final List<_BarSegment> bars;
  final List<_OverflowMarker> markers;
}

/// グリッドの上に予定バー（[EventBar]）と「+N」を絶対座標で載せるオーバーレイ
/// （Issue #72）。
///
/// TableCalendar のセル描画は 1 マス幅で切り取られてしまうため、複数日に
/// またがるバーは列をまたいだ帯として描けない。そこで同じ座標系の Stack に
/// バーを重ね、週の該当マス幅いっぱいの 1 本の帯として描く。これにより題名を
/// 全幅で表示でき、参加者色も span 全体で 1 回だけ見える。タップは
/// [IgnorePointer] で下のマスへ通す。
class _EventBarsOverlay extends StatelessWidget {
  const _EventBarsOverlay({
    required this.bars,
    required this.markers,
    required this.membersById,
    required this.daysOfWeekHeight,
    required this.rowHeight,
    required this.colWidth,
    required this.dayNumberHeight,
    required this.barSlot,
    required this.barHeight,
  });

  final List<_BarSegment> bars;
  final List<_OverflowMarker> markers;
  final Map<String, User> membersById;
  final double daysOfWeekHeight;
  final double rowHeight;
  final double colWidth;
  final double dayNumberHeight;
  final double barSlot;
  final double barHeight;

  /// バーの実開始・終了端に付ける左右の余白（マス目境界に触れないように）。
  static const double _endInset = 2;

  double _rowTop(int weekIndex) =>
      daysOfWeekHeight + weekIndex * rowHeight + dayNumberHeight;

  @override
  Widget build(BuildContext context) {
    if (colWidth <= 0 || rowHeight <= 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        for (final bar in bars)
          Positioned(
            left: bar.startCol * colWidth + (bar.roundLeft ? _endInset : 0),
            top: _rowTop(bar.weekIndex) + bar.lane * barSlot,
            width:
                (bar.endCol - bar.startCol + 1) * colWidth -
                (bar.roundLeft ? _endInset : 0) -
                (bar.roundRight ? _endInset : 0),
            height: barHeight,
            child: _buildBar(context, bar),
          ),
        for (final marker in markers)
          Positioned(
            left: marker.col * colWidth + _endInset,
            top: _rowTop(marker.weekIndex) + marker.lane * barSlot,
            width: colWidth - _endInset * 2,
            height: barHeight,
            // 「+N」はタップを下のマスへ通す（日選択の操作を保つ）。
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+${marker.count}',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBar(BuildContext context, _BarSegment bar) {
    final group = bar.group;

    // 束ねた予定（Issue #76）は代表 1 本＋人数バッジで描き、タップで内訳シートを
    // 開く。1 件だけの普通の予定はこれまでどおり [EventBar] で描き、タップは
    // [IgnorePointer] で下のマスへ通す。
    if (group.isMerged) {
      // 日別ストリップ: この週スライスの各日で active なメンバーの色を積む。
      final dayColors = [
        for (final ids in bar.perDayMemberIds)
          [for (final id in ids) colorFromHex(membersById[id]?.color ?? '')],
      ];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showEventGroupSheet(context, group, membersById),
        child: MergedEventBar(
          title: group.title,
          dayColors: dayColors,
          participantCount: group.participantCount,
          type: group.type,
          roundLeft: bar.roundLeft,
          roundRight: bar.roundRight,
        ),
      );
    }

    final colors = group.memberIds
        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
        .toList();
    return IgnorePointer(
      child: EventBar(
        title: group.title,
        colors: colors,
        type: group.type,
        roundLeft: bar.roundLeft,
        roundRight: bar.roundRight,
      ),
    );
  }
}

/// 曜日ヘッダの 1 マス（「日」〜「土」）。
class _DayOfWeekLabel extends StatelessWidget {
  const _DayOfWeekLabel({required this.day});

  static const _names = ['日', '月', '火', '水', '木', '金', '土'];

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final washiColors = KanSukeColors.of(context);
    final Color color;
    if (day.weekday == DateTime.sunday) {
      color = washiColors.sunday;
    } else if (day.weekday == DateTime.saturday) {
      color = washiColors.saturday;
    } else {
      color = scheme.onSurfaceVariant;
    }

    return Center(
      child: Text(
        // DateTime.weekday は月曜=1・日曜=7。日曜始まりの並びに合わせる。
        _names[day.weekday % 7],
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// カレンダーの 1 マス（1 日分のセル）。
///
/// 枠線でグリッドを形成し、上部に日付（＋祝日名）を描く。予定バーはこのマスの
/// 上に載る [_EventBarsOverlay] が描くため、マス自体は日付ラベルのみを持つ
/// （Issue #72）。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;

  static const double _headerHeight = 22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final washiColors = KanSukeColors.of(context);
    final holidayName = isOutside ? null : japaneseHolidayName(day);

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
              child: _dayLabel(scheme, washiColors, holidayName),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayLabel(
    ColorScheme scheme,
    KanSukeColors washiColors,
    String? holidayName,
  ) {
    final isHoliday = holidayName != null;
    final Color numberColor;
    if (isOutside) {
      numberColor = scheme.onSurface.withValues(alpha: 0.35);
    } else if (isHoliday || day.weekday == DateTime.sunday) {
      numberColor = washiColors.sunday;
    } else if (day.weekday == DateTime.saturday) {
      numberColor = washiColors.saturday;
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
            color: KanSukeColors.of(context).holiday,
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
/// 幅は親（[_EventBarsOverlay] の Positioned）に合わせて広がる。
///
/// [roundLeft] / [roundRight] は、複数日にまたがる予定（Issue #56 / #72）で
/// 週をまたぐ継続端の角丸/枠線を外すために使う。これにより次週へ描かれた
/// 同じ予定のバーと視覚的につながって見える。
///
/// [showTitle] を false にするとタイトルを描画しない。
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

/// 束ねた予定グループを表す代表 1 本のバー（Issue #76、Form B）。
///
/// 人ごとに期間が違う同名予定を 1 本に畳むため、参加者色で全面を塗る代わりに
/// 中立色（surfaceVariant）を地にする。末尾に `👥N`（N = のべ参加者の重複排除数）を
/// 出し、タイトルはグループ共通なので先頭に 1 回だけ表示する。仮/確定が混在する
/// 場合は [type] を仮として渡し、[EventBar] と同じ枠付き・半透明の仮スタイルにする
/// （FR-3、安全側）。
///
/// [dayColors] は「このバースライスの各日で実際に参加しているメンバーの色」で、
/// 1 要素 = 1 日（列）に対応する。予定が入っている日にだけ、その日の参加者色の
/// 〇（ドット）を並べて描く。長い予定に短い予定が重なるケースでも、「7/18 始まり
/// ＝全員」という誤解を避け、誰がどの日に関わるかを一目で示す（FR-2）。
class MergedEventBar extends StatelessWidget {
  const MergedEventBar({
    required this.title,
    required this.dayColors,
    required this.participantCount,
    required this.type,
    this.roundLeft = true,
    this.roundRight = true,
    super.key,
  });

  final String title;
  final List<List<Color>> dayColors;
  final int participantCount;
  final EventType type;
  final bool roundLeft;
  final bool roundRight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = type == EventType.confirmed;
    // タイトル/バッジのチップ地色。ドットと重なっても読めるよう、バー本体と
    // 同じ不透明色を敷いて背面のドットを隠す。
    final barColor = scheme.surfaceContainerHighest;
    final textColor = scheme.onSurfaceVariant;
    const radius = Radius.circular(3);
    final border = BorderSide(color: scheme.outline, width: 1);

    Widget chip(Widget child) => ColoredBox(
      color: barColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: child,
      ),
    );

    return Container(
      height: 16,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: barColor,
        // 仮が混じるグループは枠付きで種別を区別する（FR-3、安全側）。
        border: confirmed
            ? null
            : Border(
                top: border,
                bottom: border,
                left: roundLeft ? border : BorderSide.none,
                right: roundRight ? border : BorderSide.none,
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
          // 背面: 予定が入っている日に、その日の参加者色の〇をバー高いっぱいに
          // 近いサイズで並べる（FR-2）。
          Positioned.fill(child: _DayDots(dayColors: dayColors)),
          // 前面: タイトル（先頭に 1 回）と人数バッジ。チップでドットの上に載せる。
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Flexible(
                    child: chip(
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.0,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  chip(
                    Text(
                      '👥$participantCount',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.0,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 束ねたバーの日別ドット（Issue #76）。
///
/// 幅を日数で等分し、予定が入っている日にだけ、その日の参加者色の〇を横並びで
/// 描く。予定のない日は空ける。〇はバー高と同等〜気持ち小さいサイズにし、
/// 一目で判別できるようにする。
class _DayDots extends StatelessWidget {
  const _DayDots({required this.dayColors});

  final List<List<Color>> dayColors;

  /// 〇の直径。バー高（16）より気持ち小さくして上下に少し余白を残す。
  static const double _dotSize = 12;

  @override
  Widget build(BuildContext context) {
    if (dayColors.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = constraints.maxWidth / dayColors.length;
        return Row(
          children: [
            for (final colors in dayColors)
              SizedBox(
                width: dayWidth,
                height: constraints.maxHeight,
                child: colors.isEmpty
                    ? null
                    : Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final color in colors)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: Container(
                                  width: _dotSize,
                                  height: _dotSize,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }
}

/// 束ねた予定グループの内訳ボトムシート（Issue #76）。
///
/// グループ内の各予定を参加者・期間・仮/確定つきで一覧し、行タップで既存の
/// 予定編集画面へ遷移する。マージは表示上の導出なので、編集は各予定に対して
/// 個別に行う（データは各自のまま）。
Future<void> _showEventGroupSheet(
  BuildContext context,
  EventGroup group,
  Map<String, User> membersById,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                group.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: group.events.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final event = group.events[index];
                  return _EventGroupSheetTile(
                    event: event,
                    membersById: membersById,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 内訳シートの 1 行（1 予定）。行タップで予定編集画面へ遷移する（Issue #76）。
class _EventGroupSheetTile extends StatelessWidget {
  const _EventGroupSheetTile({required this.event, required this.membersById});

  final Event event;
  final Map<String, User> membersById;

  @override
  Widget build(BuildContext context) {
    final colors = event.memberIds
        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
        .toList();
    final names = event.memberIds
        .map((id) => membersById[id]?.name.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();

    return ListTile(
      leading: Wrap(
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
      title: Text(names.isEmpty ? '（参加者なし）' : names.join('・')),
      subtitle: Text(_periodLabel(event)),
      trailing: EventTypeBadge(event.type),
      onTap: () {
        // シートを閉じてから編集画面へ遷移する（シートを残さない）。
        Navigator.pop(context);
        Navigator.pushNamed(
          context,
          AppRoutes.eventEdit,
          arguments: EventEditArgs.edit(event),
        );
      },
    );
  }

  String _periodLabel(Event event) {
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    String two(int value) => value.toString().padLeft(2, '0');
    String monthDay(DateTime dt) => '${dt.month}/${dt.day}';
    String time(DateTime dt) => '${two(dt.hour)}:${two(dt.minute)}';

    if (event.allDay) {
      return sameDay
          ? '${monthDay(start)}・終日'
          : '${monthDay(start)}〜${monthDay(end)}・終日';
    }
    if (!sameDay) {
      return '${monthDay(start)} ${time(start)}〜${monthDay(end)} ${time(end)}';
    }
    return '${monthDay(start)} ${time(start)}〜${time(end)}';
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

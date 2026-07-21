import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/color_utils.dart';
import '../../../core/japanese_holidays.dart';
import '../../../core/logger.dart';
import '../../../core/member_display.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
import '../../calendars/presentation/calendar_switcher.dart';
import '../../events/application/event_filter.dart';
import '../../events/application/event_grouping.dart';
import '../../events/application/event_ordering.dart';
import '../../events/application/event_providers.dart';
import '../../events/presentation/event_edit_args.dart';
import '../../events/presentation/event_type_badge.dart';
import '../../events/presentation/member_filter_button.dart';
import '../../settings/application/event_merge_provider.dart';
import '../../settings/application/multi_member_display_provider.dart';
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

  /// Issue #126: 横画面など行が低く、既定寸法（[_dayNumberHeight] ＋ [_barSlot]）
  /// では帯が 1 本も入らないときに使う圧縮寸法。日付欄と行間だけを詰め、帯自体の
  /// 高さ（[_barHeight]）は変えないので可読性は保ったまま「+N」だけになるのを
  /// 防ぎ、どの日も最低 1 件は帯（情報）を出す（「帯が細くなってもいいから一つは
  /// 情報がほしい」というフィードバックに対応）。
  static const double _dayNumberHeightCompact = 15;
  static const double _barSlotCompact = 17;

  /// 横スワイプを月送りと判定する速度しきい値（論理px/秒）。
  static const double _swipeVelocityThreshold = 200;

  /// Issue #134: 月切替時にカレンダーをスライドさせるアニメーションの長さ。
  static const Duration _monthTransitionDuration = Duration(milliseconds: 280);

  /// Issue #134: 直前に描いた月（年月キー）。ビルド時に現在の月と比較して
  /// スライド方向（進む/戻る）を決めるために保持する。初回は null。
  DateTime? _prevMonthKey;

  /// Issue #134: 月送りの向き。true＝翌月へ（新しい月が右から入る）、
  /// false＝前月へ（左から入る）。[build] で [_prevMonthKey] と比較して更新する。
  bool _slideForward = true;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialFocusedDay ?? DateTime.now();
  }

  /// 画面に実際に見えている 6 週グリッドの範囲 `[先頭日, 最終日の翌日)`。
  ///
  /// Issue #59 / FR-4: 前後月の日付セルも表示しているため、そのセルの予定も
  /// 読み込む。バーの配置計算はこの範囲を基準にする。
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

  /// 予定の取得範囲。表示中グリッドの前後 1 グリッド分（6 週）を広げる。
  ///
  /// Issue #108: マージ表示（Issue #76）は同名・期間が連なる予定を 1 グループに
  /// 束ねるが、取得をグリッドの 42 日ちょうどに絞ると、連なりの一部（例: 早く
  /// 終わる子の夏休み）が翌月のグリッドと重ならず取得されない。するとグループの
  /// 構成が月ビューごとに変わり、同じ日の帯が月によってマージ帯になったり単独の
  /// 予定バーになったりと表示がずれる。グリッド外へ続く連なりも束ねたまま描ける
  /// よう、取得は前後へパディングする（それ以上離れた連なりは束ね対象として
  /// 追跡しない）。表示するバー自体は従来どおり [_visibleCalendarRange] で
  /// クリップするため、増えるのは取得量のみで描画は変わらない（NFR-1）。
  DateRange get _eventFetchRange {
    final visible = _visibleCalendarRange;
    const padding = Duration(days: _weekRows * 7);
    return (
      start: visible.start.subtract(padding),
      end: visible.end.add(padding),
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
    // Issue #134: 表示中の月（年月キー）。直前に描いた月と比べて、月が変わった
    // ときだけスライドの向きを更新する。データ更新などで月が変わらない再描画では
    // 向きを保ち、余計なスライドを起こさない。
    final monthKey = DateTime(_focusedDay.year, _focusedDay.month);
    if (_prevMonthKey != null && monthKey != _prevMonthKey) {
      _slideForward = monthKey.isAfter(_prevMonthKey!);
    }
    _prevMonthKey = monthKey;

    // Issue #108: 取得はグリッドより広い範囲で行い、月をまたいで連なる予定の
    // マージ構成が月ビューごとに変わらないようにする。
    final fetchRange = _eventFetchRange;
    final calendarId = ref.watch(selectedCalendarIdProvider);
    final eventsAsync = ref.watch(
      eventsInRangeProvider((
        start: fetchRange.start,
        end: fetchRange.end,
        calendarId: calendarId,
      )),
    );
    final membersById = ref.watch(membersByIdProvider);
    final currentUid = ref.watch(currentUidProvider);
    final mergeEnabled = ref.watch(resolvedEventMergeEnabledProvider);
    // Issue #112: 複数人予定の色の見せ方（丸マーク／色分け）は設定に従う。
    final multiMemberDisplay = ref.watch(
      resolvedMultiMemberEventDisplayProvider,
    );
    // Issue #78: 参加者フィルタが有効なら、選択メンバーを含む予定だけに絞る
    // （表示上の絞り込みのみ。データは変更しない）。
    final memberFilter = ref.watch(memberFilterProvider);
    final events = filterEventsByMembers(
      eventsAsync.asData?.value ?? const <Event>[],
      memberFilter,
    );
    if (eventsAsync.hasError) {
      AppLogger.error(
        'eventsInRangeProvider errored for $fetchRange/$calendarId',
        tag: 'CalendarScreen',
        error: eventsAsync.error,
        stackTrace: eventsAsync.stackTrace,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const CalendarSwitcherTitle(),
        actions: [
          const MemberFilterButton(),
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
                // Issue #126: 既定寸法（日付欄 [_dayNumberHeight] ＋帯スロット
                // [_barSlot]）が 1 行分も入らない低い行（横画面など）では、日付欄と
                // 行間を詰めた圧縮寸法へ切り替える。これにより予定が 1 件も見えず
                // 「+N」だけになる状態を避け、最低 1 件は帯を出す。
                final compact = rowHeight - _dayNumberHeight - 2 < _barSlot;
                final dayNumberHeight = compact
                    ? _dayNumberHeightCompact
                    : _dayNumberHeight;
                final barSlot = compact ? _barSlotCompact : _barSlot;
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
                  dayNumberHeight: dayNumberHeight,
                  barSlot: barSlot,
                );
                // Issue #72 / #134: TableCalendar 内蔵の横スワイプ（PageView）は
                // グリッドだけを動かし、上に重ねたバーのオーバーレイと同期しない
                // ため無効化している。代わりに横フリックを自前で拾って月送りし、
                // グリッドとバーをまとめた 1 枚（下の [SizedBox]）を
                // [AnimatedSwitcher] でスライドさせる。これによりグリッドとバーが
                // ずれないまま、月が変わったことをスライドで示せる（Issue #134）。
                final page = SizedBox(
                  key: ValueKey(monthKey),
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Stack(
                    children: [
                      _buildCalendar(compact),
                      // バーはグリッドの上に載せる。普通のバー・「+N」は
                      // [IgnorePointer] でタップを下のマスへ通し、「日を選択→
                      // 再タップで日別一覧」の操作を保つ。束ねたバー（Issue #76）
                      // だけは自身でタップを受け、内訳シートを開く。
                      Positioned.fill(
                        child: _EventBarsOverlay(
                          bars: layout.bars,
                          markers: layout.markers,
                          membersById: membersById,
                          currentUid: currentUid,
                          multiMemberDisplay: multiMemberDisplay,
                          daysOfWeekHeight: _daysOfWeekHeight,
                          rowHeight: rowHeight,
                          colWidth: colWidth,
                          dayNumberHeight: dayNumberHeight,
                          barSlot: barSlot,
                          barHeight: _barHeight,
                        ),
                      ),
                    ],
                  ),
                );
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
                  child: AnimatedSwitcher(
                    duration: _monthTransitionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // 月が変わると新旧 2 枚が同時に生き、逆向きにスライドする。
                    // スワイプ方向と月の進退を一致させるため、進む向きでは新しい月を
                    // 右（Offset(1,0)）から入れて古い月を左へ、戻る向きでは逆にする。
                    transitionBuilder: (child, animation) {
                      final incoming =
                          (child.key as ValueKey?)?.value == monthKey;
                      final begin = _slideForward
                          ? (incoming
                                ? const Offset(1, 0)
                                : const Offset(-1, 0))
                          : (incoming
                                ? const Offset(-1, 0)
                                : const Offset(1, 0));
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      );
                    },
                    child: page,
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

  Widget _buildCalendar(bool compact) {
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
        compact: compact,
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
      // Issue #72 / #134: 横スワイプ／ページ送りアニメーションはグリッドだけを
      // 動かしオーバーレイと同期しないため止める。月送りは自前の横フリックと
      // ヘッダのボタンで行い、スライドはグリッド＋バーをまとめて包んだ
      // [AnimatedSwitcher]（build 内）が担う。
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
    required double dayNumberHeight,
    required double barSlot,
  }) {
    final firstVisibleDay = _dateKey(range.start);
    final lastVisibleDay = _dateKey(
      range.end,
    ).subtract(const Duration(days: 1));

    // マスの高さから、表示できるバー本数を見積もる（[_DayCell] と同じ基準）。
    // Issue #126: 圧縮時は詰めた日付欄高・行間で見積もる。
    final available = rowHeight - dayNumberHeight - 2;
    var capacity = available <= 0 ? 0 : (available ~/ barSlot);
    // Issue #126: 行に日付欄ぶんの余白があるなら、帯が多少はみ出しても最低 1 本は
    // 出す（「帯が細くなってもいいから一つは情報がほしい」というフィードバック）。
    if (capacity == 0 && available > 0) {
      capacity = 1;
    }

    // グループごとに表示範囲でクリップした開始・終了日（期間の和集合）を求める。
    // startDay / endDay はクリップ前の実際の開始・終了日。グリッド外へ続く帯の
    // 端に開始・終了の角丸を付けないための判定に使う（Issue #108）。
    final clippedRanges =
        <
          EventGroup,
          ({DateTime start, DateTime end, DateTime startDay, DateTime endDay})
        >{};
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
      clippedRanges[group] = (
        start: start,
        end: end,
        startDay: groupStartDay,
        endDay: groupEndDay,
      );
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
      // Issue #126: ただし 1 行しか入らない（capacity == 1）低い行では、「+N」より
      // 1 件の帯を優先して表示し、「+N」は省く（低い行でも最低 1 件は帯が見える）。
      final int maxVisibleLanes;
      if (laneCount <= capacity) {
        maxVisibleLanes = laneCount;
      } else if (capacity <= 1) {
        maxVisibleLanes = capacity;
      } else {
        maxVisibleLanes = capacity - 1;
      }
      // 「+N」用の行を確保できたときだけマーカーを出す。確保できないまま出すと
      // 帯の真下（＝次の行）に重なって描かれてしまうため（Issue #126）。
      final showOverflowMarkers = maxVisibleLanes < capacity;

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
              // Issue #108: 比較はクリップ後（r.start / r.end）ではなく実際の
              // 開始・終了日と行う。グリッド外へ続く帯（月をまたぐ予定）の端に
              // 角丸を付けると、そこで始まる・終わるように見えてしまうため。
              roundLeft: segStart.isAtSameMomentAs(r.startDay),
              roundRight: segEnd.isAtSameMomentAs(r.endDay),
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
        if (showOverflowMarkers && hiddenPerCol[col] > 0) {
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
/// （＝週やグリッド端をまたぐ継続端ではない）かどうかを表す。[group] は 1 件のみなら
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
    required this.currentUid,
    required this.multiMemberDisplay,
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

  /// 現在サインイン中のユーザ。マージ帯に自分の予定が含まれるとき、地色を
  /// 自分の色へ寄せて「自分の予定が入っている」と一目で分かるようにする（Issue #105）。
  final String? currentUid;

  /// 複数人予定の色の見せ方（丸マーク／色分け、Issue #112）。設定に従う。
  final MultiMemberEventDisplay multiMemberDisplay;
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
      // Issue #105: 自分の予定が束ねられていると中立グレーの地色に埋もれて
      // 「自分の予定が見えない」ため、自分が参加者に含まれるなら地色を自分の
      // 色へ寄せて色で判別できるようにする（FR-2）。
      final self = currentUid != null ? membersById[currentUid] : null;
      final selfColor = self != null && group.memberIds.contains(currentUid)
          ? colorFromHex(self.color)
          : null;
      // Issue #105: 単タップで内訳シートが開くと、日を選ぶ/予定を足すつもりの
      // ミスタップでも開いてしまい煩わしい。単タップは（通常バー同様）下のマスへ
      // 通して日選択に使い、内訳シートは Web＝ダブルクリック／モバイル＝長押しで
      // 開く。translucent にして単タップをマスへ透過させる。
      void openSheet() => _showEventGroupSheet(context, group, membersById);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: kIsWeb ? openSheet : null,
        onLongPress: kIsWeb ? null : openSheet,
        child: MergedEventBar(
          title: group.title,
          dayColors: dayColors,
          type: group.type,
          roundLeft: bar.roundLeft,
          roundRight: bar.roundRight,
          selfColor: selfColor,
        ),
      );
    }

    final colors = group.memberIds
        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
        .toList();
    // Issue #112: 複数人の予定は、設定が「丸マーク」なら帯を塗り分けず、
    // タイトルの右に参加者色の〇を並べる。1 人の予定は従来どおり単色。
    final memberDots =
        multiMemberDisplay == MultiMemberEventDisplay.dots && colors.length > 1;
    // Issue #105 と同様、丸マーク表示の中立地色に自分の予定が埋もれないよう、
    // 自分が参加者なら地色を自分の色へ寄せる（FR-2）。
    final self = currentUid != null ? membersById[currentUid] : null;
    final selfColor =
        memberDots && self != null && group.memberIds.contains(currentUid)
        ? colorFromHex(self.color)
        : null;
    return IgnorePointer(
      child: EventBar(
        title: group.title,
        colors: colors,
        type: group.type,
        roundLeft: bar.roundLeft,
        roundRight: bar.roundRight,
        memberDots: memberDots,
        selfColor: selfColor,
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
    this.compact = false,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;

  /// Issue #126: 圧縮表示か。true のとき日付欄を詰め、帯 1 本ぶんの余白を空ける。
  /// [_CalendarScreenState._dayNumberHeightCompact]（15）＝上パディング(1)＋
  /// 日付ラベル高(14) に合わせる。
  final bool compact;

  double get _headerHeight => compact ? 14 : 22;

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
            // Issue #126: 圧縮時は日付の丸を一回り小さくして帯ぶんの高さを空ける。
            width: compact ? 18 : 20,
            height: compact ? 13 : 18,
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
                fontSize: compact ? 11 : 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isToday
                    ? (isHoliday ? scheme.onError : scheme.onPrimary)
                    : numberColor,
              ),
            ),
          ),
          if (holidayName != null)
            Expanded(
              child: _HolidayLabel(name: holidayName, compact: compact),
            ),
        ],
      ),
    );
  }
}

/// 祝日名ラベル（例: 「海の日」）。"祝" という記号だけでは何の祝日か
/// わからないため、名称そのものを表示して一目で判別できるようにする。
class _HolidayLabel extends StatelessWidget {
  const _HolidayLabel({required this.name, this.compact = false});

  final String name;

  /// Issue #126: 圧縮時は詰めた日付欄（高さ 14）に収まるよう余白・文字を小さくする。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: compact
          ? const EdgeInsets.only(left: 2, top: 1)
          : const EdgeInsets.only(left: 2, top: 3),
      child: Tooltip(
        message: name,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 8 : 9,
            height: 1,
            fontWeight: FontWeight.w600,
            color: KanSukeColors.of(context).holiday,
          ),
        ),
      ),
    );
  }
}

/// 中立地色（[KanSukeColors.mergedBar]）を自分の識別色へ寄せる度合い
/// （Issue #105）。メンバー色そのものにはせず、あくまで中立色を帯びる程度に
/// とどめ、地色の明度を大きく変えずタイトルの可読性を保つ。
const double _selfTintFactor = 0.28;

/// 仮の予定の地色（識別色）の不透明度（Issue #106、基本設計 §6.3「半透明」）。
///
/// 確定（塗りつぶし）と一目で区別しつつ、薄い識別色（例: 水色 #81D4FA）でも帯
/// の存在が背景に埋もれないよう、従来の 0.16 よりわずかに濃くする。
const double _tentativeFillAlpha = 0.22;

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
///
/// Issue #112: [memberDots] を true にすると、複数人の予定を色の塗り分けでは
/// なく「中立地色の帯＋タイトル右に参加者色の〇」で描く。塗り分けは 3 人以上で
/// 細切れになり見にくいというフィードバックに応えたもので、マージ帯
/// （[MergedEventBar]）と同じデザイン言語（中立地色＋色ドット）に揃える。
/// 参加者が 1 人のときは指定に関わらず従来どおり単色で塗る。
class EventBar extends StatelessWidget {
  const EventBar({
    required this.title,
    required this.colors,
    required this.type,
    this.roundLeft = true,
    this.roundRight = true,
    this.showTitle = true,
    this.memberDots = false,
    this.selfColor,
    super.key,
  });

  final String title;
  final List<Color> colors;
  final EventType type;
  final bool roundLeft;
  final bool roundRight;
  final bool showTitle;

  /// 複数人の予定を「中立地色＋参加者色の〇」で描くか（Issue #112）。
  final bool memberDots;

  /// 丸マーク表示で自分がこの予定の参加者に含まれるときの自分の識別色
  /// （Issue #105 / #112）。非 null なら中立地色をこの色へ少し寄せ、
  /// 「自分の予定が入っている」と一目で分かるようにする。
  final Color? selfColor;

  /// 参加者色の〇の直径。バー高（16）に上下の余白が残るサイズにする。
  static const double _dotSize = 10;

  @override
  Widget build(BuildContext context) {
    if (memberDots && colors.length > 1) {
      return _buildDotBar(context);
    }
    return _buildSplitBar(context);
  }

  /// 中立地色の帯＋タイトル右の参加者色〇で描く（Issue #112）。
  ///
  /// 地色・枠線・文字色はマージ帯（[MergedEventBar]）と揃え、「中立地色の帯＝
  /// 複数人の予定」という見え方を統一する。仮が含まれる予定は枠付きで種別を
  /// 区別する（FR-3）。
  Widget _buildDotBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = type == EventType.confirmed;
    final baseColor = KanSukeColors.of(context).mergedBar;
    final barColor = selfColor != null
        ? Color.lerp(baseColor, selfColor, _selfTintFactor)!
        : baseColor;
    // 地色は設定で自由に変えられるため（Issue #112 フォローアップ）、文字色は
    // 地色の明度から黒/白を選び、どの地色でも読めるようにする。
    final textColor = readableTextColor(barColor);
    const radius = Radius.circular(3);
    final border = BorderSide(color: scheme.outline, width: 1);

    return Container(
      height: 16,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: barColor,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            if (showTitle)
              Flexible(
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
            if (showTitle) const SizedBox(width: 4),
            // マスが狭く〇が収まらないときは、〇の列ごと縮めてはみ出させない。
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final color in colors)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
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
        ),
      ),
    );
  }

  /// 参加メンバーの色で帯を等分割して塗る従来表示。
  Widget _buildSplitBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = type == EventType.confirmed;
    final primary = colors.first;
    // Issue #106: 仮の文字色に識別色をそのまま使うと、薄い色（例: 水色
    // #81D4FA）では明るい背景に埋もれて読めなかった。確定と同じく実効地色
    // （仮は識別色を surface に合成した半透明相当の色）の明度から黒/白を選び、
    // どの識別色でもタイトルが読めるようにする（ドット帯・マージ帯と同じ方式）。
    Color effectiveBackground(Color color) => confirmed
        ? color
        : Color.alphaBlend(
            color.withValues(alpha: _tentativeFillAlpha),
            scheme.surface,
          );
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
      // Row+Expanded の等分割は Flutter 3.41.6 でこの構成だと塗りが
      // 描画されないため、LayoutBuilder で幅を計算し固定幅で等分割している
      // （flex レイアウトを使わない）。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final segmentWidth = width / colors.length;

          // Issue #133: 2 人以上の帯ではタイトルが隣の色にまたがるため、
          // 先頭色だけで文字色を決めると「片方の帯（例: 水色）に白文字」で
          // 埋もれた。区画ごとに同じタイトルをその区画の地色に合う文字色で
          // 描き、区画の幅でクリップすることで、どの色の上でも読めるようにする。
          Widget titleFor(Color background) => Padding(
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
                  color: readableTextColor(effectiveBackground(background)),
                ),
              ),
            ),
          );

          return Stack(
            children: [
              for (var i = 0; i < colors.length; i++)
                Positioned(
                  left: i * segmentWidth,
                  top: 0,
                  width: segmentWidth,
                  height: height,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: confirmed
                                ? colors[i]
                                : colors[i].withValues(
                                    alpha: _tentativeFillAlpha,
                                  ),
                          ),
                        ),
                        // 帯全幅ぶんのタイトルを左へずらして置き、この区画に
                        // 掛かる部分だけが見える。折り返し位置や省略記号は
                        // 全区画で同一になる。
                        if (showTitle)
                          Positioned(
                            left: -i * segmentWidth,
                            top: 0,
                            width: width,
                            height: height,
                            child: titleFor(colors[i]),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 束ねた予定グループを表す代表 1 本のバー（Issue #76、Form B）。
///
/// 人ごとに期間が違う同名予定を 1 本に畳むため、参加者色で全面を塗る代わりに
/// 中立色（surfaceVariant）を地にする。タイトルはグループ共通なので先頭に
/// 1 回だけ表示する。仮/確定が混在する
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
    required this.type,
    this.roundLeft = true,
    this.roundRight = true,
    this.selfColor,
    super.key,
  });

  final String title;
  final List<List<Color>> dayColors;
  final EventType type;
  final bool roundLeft;
  final bool roundRight;

  /// 自分がこのグループの参加者に含まれるときの自分の識別色（Issue #105）。
  /// 非 null なら地色を中立色からこの色へ少し寄せ、「自分の予定が入っている」と
  /// 一目で分かるようにする。null（自分が不参加）なら従来どおり中立色のまま。
  final Color? selfColor;

  /// タイトル行（チップの外側）の左右パディング。
  static const double _rowPadding = 2;

  /// タイトルチップ内側の左右パディング。
  static const double _chipPadding = 2;

  /// タイトルの文字スタイル。チップ右端の実測（[_chipRightEdge]）と描画で
  /// 同じ値を使い、計算と見た目がずれないようにする（Issue #125）。
  static const double _titleFontSize = 11;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = type == EventType.confirmed;
    // 束ねたバーの地色は、メンバー色（誰の予定か）と混同されないよう専用の
    // 中立色をテーマから引く（既定は KanSukeColors.mergedBar、Issue #76）。
    // タイトルのチップも同じ地色を敷き、背面のドットを隠して読めるようにする。
    // Issue #105: 自分が参加者なら中立色を自分の色へ少し寄せ、埋もれないようにする。
    final baseColor = KanSukeColors.of(context).mergedBar;
    final barColor = selfColor != null
        ? Color.lerp(baseColor, selfColor, _selfTintFactor)!
        : baseColor;
    // Issue #105: 従来の onSurfaceVariant はベージュ地で薄く「背景と同化」して
    // 見えづらかったため、コントラストの高い色にする。地色は設定で自由に変え
    // られるため（Issue #112 フォローアップ）、テーマ色ではなく地色の明度から
    // 黒/白を選び、どの地色でも読めるようにする。
    final textColor = readableTextColor(barColor);
    const radius = Radius.circular(3);
    final border = BorderSide(color: scheme.outline, width: 1);

    Widget chip(Widget child) => ColoredBox(
      color: barColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _chipPadding),
        child: child,
      ),
    );

    final titleStyle = TextStyle(
      fontSize: _titleFontSize,
      height: 1.0,
      fontWeight: FontWeight.w600,
      color: textColor,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 背面: 予定が入っている日に、その日の参加者色の〇をバー高
              // いっぱいに近いサイズで並べる（FR-2）。Issue #125: チップに
              // 一部だけ隠れた〇が欠けた形でタイトル脇にはみ出して文字と
              // 重なって見えるため、チップ右端に掛かる〇は描かない。
              Positioned.fill(
                child: _DayDots(
                  dayColors: dayColors,
                  leadingExclusion: _chipRightEdge(
                    context,
                    titleStyle,
                    constraints.maxWidth,
                  ),
                ),
              ),
              // 前面: タイトル（先頭に 1 回）。チップでドットの上に載せる。
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _rowPadding),
                  child: Row(
                    children: [
                      Flexible(
                        child: chip(
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
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
      ),
    );
  }

  /// タイトルチップの右端 x（バー内座標）を実測する（Issue #125）。
  ///
  /// 描画される [Text] と同じスタイル・スケール・省略記号で [TextPainter] に
  /// レイアウトさせ、チップのパディングを加えて右端を求める。[_DayDots] は
  /// この x に掛かる〇を描かず、タイトルと〇の重なりを防ぐ。
  double _chipRightEdge(
    BuildContext context,
    TextStyle titleStyle,
    double maxWidth,
  ) {
    final chipMaxWidth = maxWidth - (_rowPadding + _chipPadding) * 2;
    if (chipMaxWidth <= 0) {
      return maxWidth;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        // 実際の描画と同様に DefaultTextStyle（フォントファミリ等）を継承する。
        style: DefaultTextStyle.of(context).style.merge(titleStyle),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
      // [TextOverflow.ellipsis] と同じ省略記号で折り返し時の幅も一致させる。
      ellipsis: '…',
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: chipMaxWidth);
    final textWidth = painter.width;
    painter.dispose();
    return _rowPadding + _chipPadding * 2 + textWidth;
  }
}

/// 束ねたバーの日別ドット（Issue #76）。
///
/// 幅を日数で等分し、予定が入っている日にだけ、その日の参加者色の〇を横並びで
/// 描く。予定のない日は空ける。〇はバー高と同等〜気持ち小さいサイズにし、
/// 一目で判別できるようにする。
class _DayDots extends StatelessWidget {
  const _DayDots({required this.dayColors, this.leadingExclusion = 0});

  final List<List<Color>> dayColors;

  /// バー先頭からこの x 座標までに（一部でも）掛かる〇は描かない（Issue #125）。
  ///
  /// 〇はタイトルチップの背面に描くため、チップの右端が〇の途中に掛かると
  /// 欠けた〇がタイトル脇にはみ出し、文字と重なって見える。チップに完全に
  /// 隠れる〇は元々見えないので、掛かる〇ごと描かないことで表示の情報量を
  /// 変えずに重なりを解消する。
  final double leadingExclusion;

  /// 〇の直径。バー高（16）より気持ち小さくして上下に少し余白を残す。
  static const double _dotSize = 12;

  /// 〇 1 個分の横スロット（直径＋左右パディング 1）。位置計算にも使う。
  static const double _dotSpan = _dotSize + 2;

  /// この〇（[dayIndex] 日目の [dotIndex] 個目）がタイトルチップに掛からず
  /// 完全に見えるか（Issue #125）。[Center]＋[Row] のレイアウトと同じ計算で
  /// 〇の左端 x を求め、[leadingExclusion] より右にあるものだけ描く。
  bool _isDotClearOfTitle(
    int dayIndex,
    int dotIndex,
    int dotCount,
    double dayWidth,
  ) {
    if (leadingExclusion <= 0) {
      return true;
    }
    final rowWidth = dotCount * _dotSpan;
    final rowStart = dayIndex * dayWidth + (dayWidth - rowWidth) / 2;
    final dotLeft = rowStart + dotIndex * _dotSpan + 1;
    return dotLeft >= leadingExclusion;
  }

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
            for (final (dayIndex, colors) in dayColors.indexed)
              SizedBox(
                width: dayWidth,
                height: constraints.maxHeight,
                child: colors.isEmpty
                    ? null
                    : Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (dotIndex, color) in colors.indexed)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                // チップに掛かる〇は描かず、レイアウトだけ保つ
                                // 同サイズの空白に置き換える（Issue #125）。
                                child:
                                    _isDotClearOfTitle(
                                      dayIndex,
                                      dotIndex,
                                      colors.length,
                                      dayWidth,
                                    )
                                    ? Container(
                                        width: _dotSize,
                                        height: _dotSize,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : const SizedBox(
                                        width: _dotSize,
                                        height: _dotSize,
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
    // 退会済み参加者は「退会したメンバー」にフォールバックする（Issue #102）。
    final names = event.memberIds
        .map((id) => memberDisplayName(membersById[id]))
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
///
/// Issue #130: 凡例は「表示中カレンダー（[selectedCalendarIdProvider]）の参加者」だけを
/// 出す。全参加カレンダーの和集合（[familyMembersProvider]）ではなく、参加者フィルタ
/// （Issue #78）の候補と同一の [filterableMembersProvider] を購読することで、カレンダー
/// 切替に即座に追従し、凡例とフィルタ候補の表示が食い違わないようにする。
class _MemberLegend extends ConsumerWidget {
  const _MemberLegend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(filterableMembersProvider);
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

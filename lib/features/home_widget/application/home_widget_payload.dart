import 'dart:convert';

import '../../../core/japanese_holidays.dart';
import '../../../models/models.dart';
import '../../events/application/event_ordering.dart';

/// ペイロードのスキーマ版。Android 側（`KanSukeWidgetFactory` /
/// `KanSukeMonthWidgetFactory`）と揃えること。
///
/// 互換性のない形に変えるときは値を上げる。アプリだけ更新されてウィジェットの
/// プロセスが古い解釈のまま動く瞬間があるため、Android 側は版が違うペイロードを
/// 「まだ読めない」として扱い、崩れた表示を出さないようにする。
const int homeWidgetPayloadVersion = 2;

/// 月グリッドの列数（日曜〜土曜）。
const int homeWidgetColumnsPerWeek = 7;

/// 月グリッドの最大週数。
///
/// 1 日が土曜で 31 日ある月は 6 週にまたがる。ペイロードの範囲はこの最大で採り、
/// 実際に何週描くかは Android 側が描画時の月から決める。
const int homeWidgetMaxWeeksPerMonth = 6;

/// 1 日あたりにペイロードへ載せる最大件数。
///
/// リスト側もマス側も、これ以上は高さで見切れる。全件数は `total` で渡すので、
/// 月表示のマスは「+N」を正しく出せる。
const int homeWidgetMaxEntriesPerDay = 12;

/// 1 件の予定に載せる識別色（FR-2）の最大数。リストのドット数と揃える。
const int homeWidgetMaxColors = 3;

/// 識別色を引けない参加者（退会済みなど）の色。
///
/// アプリ側の `colorFromHex` のフォールバックと同じグレー。
const String homeWidgetFallbackColor = '#9E9E9E';

/// ウィジェットへ渡す JSON 文字列を組み立てる。
String encodeHomeWidgetPayload(Map<String, Object?> payload) =>
    jsonEncode(payload);

/// サインインしていないときのペイロード。
///
/// 家族の予定がホーム画面に残り続けないよう、サインアウト時はこれを書き込んで
/// 内容を消す（NFR-4）。
Map<String, Object?> buildSignedOutHomeWidgetPayload() {
  return <String, Object?>{
    'version': homeWidgetPayloadVersion,
    'signedIn': false,
    'days': <Object?>[],
  };
}

/// [firstOfMonth] の月グリッドの開始日（1 日を含む週の日曜）。
///
/// アプリの月表示（table_calendar）と同じ日曜始まり。
DateTime homeWidgetGridStart(DateTime firstOfMonth) {
  // DateTime.weekday は月曜=1・日曜=7。日曜始まりの並びに合わせる。
  final leadingDays = firstOfMonth.weekday % homeWidgetColumnsPerWeek;
  return DateTime(
    firstOfMonth.year,
    firstOfMonth.month,
    firstOfMonth.day - leadingDays,
  );
}

/// ペイロードが覆う日の範囲（[start] 以上 [end] 未満）。
///
/// **今月のグリッド開始から翌月のグリッド終了まで**を渡す。どの月を描くかは
/// 描画時の Android 側が決めるため、月をまたいだ直後にアプリを開いていなくても
/// グリッドが空にならないよう、翌月ぶんまで含める。今日から 1 週間先まで
/// （リスト側のウィジェットが見る範囲）も必ずこの中に入る。
({DateTime start, DateTime end}) homeWidgetDayRange(DateTime now) {
  final today = _dateOnly(now.toLocal());
  final start = homeWidgetGridStart(DateTime(today.year, today.month, 1));
  final nextMonthGridStart = homeWidgetGridStart(
    DateTime(today.year, today.month + 1, 1),
  );
  final end = DateTime(
    nextMonthGridStart.year,
    nextMonthGridStart.month,
    nextMonthGridStart.day +
        homeWidgetMaxWeeksPerMonth * homeWidgetColumnsPerWeek,
  );
  return (start: start, end: end);
}

/// ホーム画面ウィジェットへ渡す予定データを組み立てる（Issue #127）。
///
/// [homeWidgetDayRange] の各日について、その日に重なる予定を日別一覧と同じ並び
/// （[orderEventsForDisplay]）で並べる。[events] は表示中カレンダー（FR-8）の
/// 予定を渡す前提で、絞り込みはしない。
///
/// [mergedBarColor] は複数人の予定に使うまとめ帯の地色（`#RRGGBB`、Issue #112 の
/// 設定値）。null ならウィジェット側のテーマ既定色を使う（ライト/ダークのどちらで
/// 描かれるかは描画時に決まるため、既定色は Android 側の色リソースに持たせる）。
///
/// 予定の日時は Firestore から UTC で届くため、日の切り出しと時刻表記は
/// すべて `toLocal()` してから行う（日別一覧の `_scheduleLabel` と同じ扱い）。
Map<String, Object?> buildHomeWidgetPayload({
  required List<Event> events,
  required Map<String, User> membersById,
  required DateTime now,
  String? currentUid,
  String? mergedBarColor,
}) {
  final range = homeWidgetDayRange(now);
  final days = <Map<String, Object?>>[];
  for (
    var day = range.start;
    day.isBefore(range.end);
    // 日付の加算は DateTime(y, m, d + 1) で行う。Duration の加算は夏時間のある
    // 地域で 1 日ぶんずれるため（日本では起きないが、暦日の計算として素直）。
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    final onDay = [
      for (final event in events)
        if (_overlapsDay(event, day, nextDay)) event,
    ];
    final ordered = orderEventsForDisplay(onDay, currentUid);
    // FR-4: 祝日は月表示で見落としにくいよう、名称ごと渡す。
    final holiday = japaneseHolidayName(day);
    days.add(<String, Object?>{
      'date': formatHomeWidgetDate(day),
      'holiday': ?holiday,
      // 「+N」を正しく出せるよう、載せた件数ではなく全件数を渡す。
      'total': ordered.length,
      'entries': [
        for (final event in ordered.take(homeWidgetMaxEntriesPerDay))
          _entryOf(event, day, membersById),
      ],
    });
  }

  return <String, Object?>{
    'version': homeWidgetPayloadVersion,
    'signedIn': true,
    'mergedBarColor': ?mergedBarColor,
    'days': days,
  };
}

/// ペイロードの日付キー（`yyyy-MM-dd`）。Android 側が日を引く鍵。
String formatHomeWidgetDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${_two(day.month)}-${_two(day.day)}';

/// [day]（当日 0 時）〜[nextDay]（翌日 0 時）に予定が重なるか。
///
/// 判定は `EventRepository.watchRange` の範囲判定と同じ（終日単日予定は
/// `startAt == endAt` のため終了境界を含める）。
bool _overlapsDay(Event event, DateTime day, DateTime nextDay) {
  final start = event.startAt.toLocal();
  final end = event.endAt.toLocal();
  return start.isBefore(nextDay) && !end.isBefore(day);
}

Map<String, Object?> _entryOf(
  Event event,
  DateTime day,
  Map<String, User> membersById,
) {
  return <String, Object?>{
    'title': event.title,
    'time': homeWidgetTimeLabel(event, day),
    // FR-2: 「誰の予定か」を色で示す。リストはドット、月表示のマスは帯の地色に使う
    // （1 人なら本人の色、複数人ならまとめ帯の地色。アプリの月表示と同じ扱い）。
    'colors': [
      for (final id in event.memberIds.take(homeWidgetMaxColors))
        _colorOf(membersById[id]),
    ],
    // FR-3: 仮の予定は確定と区別できるようにする。
    'tentative': event.type == EventType.tentative,
  };
}

String _colorOf(User? member) {
  final color = member?.color.trim();
  return (color == null || color.isEmpty) ? homeWidgetFallbackColor : color;
}

/// [day] の行に出す時刻表記。
///
/// 幅の狭いウィジェットに収めるため、日別一覧のような期間表記（`7/27 22:00〜…`）
/// ではなく「その日にとって何時の予定か」だけを出す。
/// - 終日、およびその日を丸ごと覆う予定 → `終日`
/// - その日に始まる → `09:00`
/// - その日に終わる（前日から続く） → `〜10:30`
String homeWidgetTimeLabel(Event event, DateTime day) {
  if (event.allDay) return '終日';
  final start = event.startAt.toLocal();
  if (_isSameDate(start, day)) {
    return '${_two(start.hour)}:${_two(start.minute)}';
  }
  final end = event.endAt.toLocal();
  if (_isSameDate(end, day)) return '〜${_two(end.hour)}:${_two(end.minute)}';
  return '終日';
}

bool _isSameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

DateTime _dateOnly(DateTime dateTime) =>
    DateTime(dateTime.year, dateTime.month, dateTime.day);

String _two(int value) => value.toString().padLeft(2, '0');

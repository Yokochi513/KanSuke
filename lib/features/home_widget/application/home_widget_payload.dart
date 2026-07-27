import 'dart:convert';

import '../../../models/models.dart';
import '../../events/application/event_ordering.dart';

/// ペイロードのスキーマ版。Android 側（`KanSukeWidgetFactory`）と揃えること。
///
/// 互換性のない形に変えるときは値を上げる。アプリだけ更新されてウィジェットの
/// プロセスが古い解釈のまま動く瞬間があるため、Android 側は版が違うペイロードを
/// 「まだ読めない」として扱い、崩れた表示を出さないようにする。
const int homeWidgetPayloadVersion = 1;

/// ペイロードに載せる日数（今日を含む）。
///
/// ウィジェットが表示するのは今日と明日の 2 日分だが、**どの日を今日とみなすかは
/// 描画時の Android 側**が決める。アプリを何日か開かなくても日付の繰り上がりに
/// ついていけるよう、1 週間分を先に渡しておく。
const int homeWidgetDayCount = 8;

/// 1 日あたりにペイロードへ載せる最大件数。
///
/// ウィジェットの高さでどのみち見切れるため、際限なく渡さない
/// （SharedPreferences に載せる文字列なので小さく保つ）。
const int homeWidgetMaxEntriesPerDay = 12;

/// 1 件の予定に載せる識別色（FR-2）の最大数。ウィジェットのドット数と揃える。
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

/// ホーム画面ウィジェットへ渡す予定データを組み立てる（Issue #127）。
///
/// [now] の暦日（端末ローカル）から [dayCount] 日分を日ごとに切り出し、各日に
/// 重なる予定を日別一覧と同じ並び（[orderEventsForDisplay]）で並べる。
/// [events] は表示中カレンダー（FR-8）の予定を渡す前提で、絞り込みはしない。
///
/// 予定の日時は Firestore から UTC で届くため、日の切り出しと時刻表記は
/// すべて `toLocal()` してから行う（日別一覧の `_scheduleLabel` と同じ扱い）。
Map<String, Object?> buildHomeWidgetPayload({
  required List<Event> events,
  required Map<String, User> membersById,
  required DateTime now,
  String? currentUid,
  int dayCount = homeWidgetDayCount,
}) {
  final today = _dateOnly(now.toLocal());
  final days = <Map<String, Object?>>[];
  for (var offset = 0; offset < dayCount; offset += 1) {
    // 日付の加算は DateTime(y, m, d + n) で行う。Duration の加算は夏時間のある
    // 地域で 1 日ぶんずれるため（日本では起きないが、暦日の計算として素直）。
    final day = DateTime(today.year, today.month, today.day + offset);
    final nextDay = DateTime(today.year, today.month, today.day + offset + 1);
    final onDay = [
      for (final event in events)
        if (_overlapsDay(event, day, nextDay)) event,
    ];
    days.add(<String, Object?>{
      'date': formatHomeWidgetDate(day),
      'entries': [
        for (final event in orderEventsForDisplay(
          onDay,
          currentUid,
        ).take(homeWidgetMaxEntriesPerDay))
          _entryOf(event, day, membersById),
      ],
    });
  }

  return <String, Object?>{
    'version': homeWidgetPayloadVersion,
    'signedIn': true,
    'days': days,
  };
}

/// ペイロードの日付キー（`yyyy-MM-dd`）。Android 側が今日／明日を引く鍵。
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
    // FR-2: 「誰の予定か」を色で示す。ドットの数だけ渡す。
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

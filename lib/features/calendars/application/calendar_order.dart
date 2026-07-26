import '../../../models/models.dart';

/// 保存済みの並び順（カレンダー ID のリスト）に従ってカレンダーを並べ替える
/// （FR-8 / Issue #168）。
///
/// - [order] に含まれる ID は、その順番で先頭に並ぶ。
/// - [order] に無いカレンダー（新規作成・新規参加したもの）は末尾に名前昇順で並ぶ。
/// - [order] にあるが参加していない ID（退出済み・削除済み）は無視する。
List<Calendar> sortCalendarsByOrder(
  List<Calendar> calendars,
  List<String> order,
) {
  final byId = {for (final calendar in calendars) calendar.id: calendar};
  final sorted = <Calendar>[];
  final placed = <String>{};
  for (final id in order) {
    final calendar = byId[id];
    // 参加していない ID は読み飛ばす（重複 ID も 1 回だけ並べる）。
    if (calendar == null || !placed.add(id)) {
      continue;
    }
    sorted.add(calendar);
  }
  final rest =
      calendars.where((calendar) => !placed.contains(calendar.id)).toList()
        ..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });
  return [...sorted, ...rest];
}

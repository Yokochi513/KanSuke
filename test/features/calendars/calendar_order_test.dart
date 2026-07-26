import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_order.dart';
import 'package:kansuke/models/models.dart';

Calendar _calendar(String id, String name) {
  return Calendar(
    id: id,
    name: name,
    memberIds: const ['me'],
    creatorId: 'me',
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );
}

List<String> _ids(List<Calendar> calendars) => [
  for (final calendar in calendars) calendar.id,
];

void main() {
  group('sortCalendarsByOrder（Issue #168）', () {
    final a = _calendar('a', 'あさ');
    final b = _calendar('b', 'いえ');
    final c = _calendar('c', 'うみ');

    test('保存済みの順序どおりに並べ替える', () {
      expect(_ids(sortCalendarsByOrder([a, b, c], ['c', 'a', 'b'])), [
        'c',
        'a',
        'b',
      ]);
    });

    test('順序が未保存なら名前昇順のまま', () {
      expect(_ids(sortCalendarsByOrder([a, b, c], const [])), ['a', 'b', 'c']);
    });

    test('順序に含まれないカレンダーは末尾に名前昇順で並ぶ', () {
      // 新規作成・新規参加したカレンダーは末尾に回す。
      expect(_ids(sortCalendarsByOrder([c, b, a], ['c'])), ['c', 'a', 'b']);
    });

    test('参加していないカレンダー ID は無視する', () {
      // 退出済み・削除済みの ID が残っていてもエラーにならない。
      expect(_ids(sortCalendarsByOrder([a, b], ['gone', 'b', 'a'])), [
        'b',
        'a',
      ]);
    });

    test('順序に同じ ID が重複していても 1 回だけ並べる', () {
      expect(_ids(sortCalendarsByOrder([a, b], ['b', 'b'])), ['b', 'a']);
    });

    test('カレンダーが空なら空を返す', () {
      expect(sortCalendarsByOrder(const [], ['a']), isEmpty);
    });
  });
}

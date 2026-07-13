import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
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

Future<ProviderContainer> _containerWith(List<Calendar> calendars) async {
  final container = ProviderContainer(
    overrides: [
      myCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
    ],
  );
  addTearDown(container.dispose);
  // リスナーが無いとストリームの購読が pause されたままになるため、画面と同じく
  // 監視状態にしてから最初の値を待つ。
  container.listen(myCalendarsProvider, (_, _) {});
  await container.read(myCalendarsProvider.future);
  return container;
}

void main() {
  group('selectedCalendarIdProvider（FR-8）', () {
    test('未選択なら参加カレンダーの先頭（＝個人カレンダー）を表示する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      expect(container.read(selectedCalendarIdProvider), 'personal');
    });

    test('選択したカレンダーを表示する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      container.read(calendarSelectionProvider.notifier).state = 'shared';

      expect(container.read(selectedCalendarIdProvider), 'shared');
    });

    test('選択が参加カレンダーに無ければ先頭へフォールバックする', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
      ]);

      // 参加していない（他端末で選ばれた・外された）カレンダーは表示しない。
      container.read(calendarSelectionProvider.notifier).state = 'gone';

      expect(container.read(selectedCalendarIdProvider), 'personal');
    });

    test('参加カレンダーが未取得なら空になる', () async {
      final container = await _containerWith([]);

      expect(container.read(selectedCalendarIdProvider), '');
    });
  });
}

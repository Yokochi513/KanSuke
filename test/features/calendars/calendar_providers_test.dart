import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ProviderContainer _container(List<Calendar> calendars) {
  final container = ProviderContainer(
    overrides: [
      myCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _containerWith(List<Calendar> calendars) async {
  final container = _container(calendars);
  // リスナーが無いとストリームの購読が pause されたままになるため、画面と同じく
  // 監視状態にしてから最初の値を待つ。
  container.listen(myCalendarsProvider, (_, _) {});
  await container.read(myCalendarsProvider.future);
  // 保存済みの選択（Issue #167）を読み終えるまでは表示対象が決まらない。
  await container.read(calendarSelectionProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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

      await container.read(calendarSelectionProvider.notifier).select('shared');

      expect(container.read(selectedCalendarIdProvider), 'shared');
    });

    test('選択が参加カレンダーに無ければ先頭へフォールバックする', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
      ]);

      // 参加していない（他端末で選ばれた・外された）カレンダーは表示しない。
      await container.read(calendarSelectionProvider.notifier).select('gone');

      expect(container.read(selectedCalendarIdProvider), 'personal');
    });

    test('参加カレンダーが未取得なら空になる', () async {
      final container = await _containerWith([]);

      expect(container.read(selectedCalendarIdProvider), '');
    });
  });

  group('カレンダーの並び順（Issue #168）', () {
    test('並べ替えた順序を端末ローカルに保存する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      await container.read(calendarOrderProvider.future);

      await container.read(calendarOrderProvider.notifier).save([
        'shared',
        'personal',
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('calendars.order'), ['shared', 'personal']);
    });

    test('起動時に保存済みの並び順を復元する', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.order': ['shared', 'personal'],
      });

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      await container.read(calendarOrderProvider.future);

      expect(
        [for (final c in container.read(orderedCalendarsProvider)) c.id],
        ['shared', 'personal'],
      );
    });

    test('並び順が未保存なら名前昇順（Firestore のクエリ順）のまま', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      await container.read(calendarOrderProvider.future);

      expect(
        [for (final c in container.read(orderedCalendarsProvider)) c.id],
        ['personal', 'shared'],
      );
    });
  });

  group('起動時のカレンダー復元（Issue #167）', () {
    test('切り替えたカレンダー ID を端末ローカルに保存する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      await container.read(calendarSelectionProvider.notifier).select('shared');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('calendars.selected_id'), 'shared');
    });

    test('起動時に保存済みのカレンダーを復元する', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.selected_id': 'shared',
      });

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      expect(container.read(selectedCalendarIdProvider), 'shared');
    });

    test('保存済みのカレンダーを退出済みなら先頭へフォールバックする', () async {
      SharedPreferences.setMockInitialValues({'calendars.selected_id': 'gone'});

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
      ]);

      expect(container.read(selectedCalendarIdProvider), 'personal');
    });

    test('保存済みの選択を読み込み終えるまでは先頭を表示せず空になる', () async {
      // 先に一覧の先頭を返すと、読み込み完了時に別カレンダーへ切り替わってちらつく。
      SharedPreferences.setMockInitialValues({
        'calendars.selected_id': 'shared',
      });
      final container = _container([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      container.listen(myCalendarsProvider, (_, _) {});
      await container.read(myCalendarsProvider.future);

      // カレンダー一覧だけ揃い、保存済みの選択はまだ読み込み中の状態。
      expect(container.read(calendarSelectionProvider).isLoading, isTrue);
      expect(container.read(selectedCalendarIdProvider), '');

      await container.read(calendarSelectionProvider.future);

      expect(container.read(selectedCalendarIdProvider), 'shared');
    });
  });
}

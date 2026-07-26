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

  group('複数カレンダーの同時表示（Issue #170）', () {
    List<String> visibleIds(ProviderContainer container) =>
        container.read(visibleCalendarIdsProvider);

    test('複数のカレンダーを選ぶと重ねて表示する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      await container.read(calendarSelectionProvider.notifier).setVisible([
        'personal',
        'shared',
      ]);

      expect(visibleIds(container), ['personal', 'shared']);
    });

    test('表示中カレンダーは表示順（Issue #168）に整列して返す', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.order': ['shared', 'personal'],
      });
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      await container.read(calendarOrderProvider.future);

      // 選んだ順ではなく、管理画面で並べ替えた順に揃える。
      await container.read(calendarSelectionProvider.notifier).setVisible([
        'personal',
        'shared',
      ]);

      expect(visibleIds(container), ['shared', 'personal']);
    });

    test('新規作成の既定カレンダーは表示中の先頭（表示順の先頭）になる', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.order': ['shared', 'personal'],
      });
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      await container.read(calendarOrderProvider.future);

      await container.read(calendarSelectionProvider.notifier).setVisible([
        'personal',
        'shared',
      ]);

      expect(container.read(selectedCalendarIdProvider), 'shared');
    });

    test('表示中カレンダー集合を端末ローカルに保存する', () async {
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      await container.read(calendarSelectionProvider.notifier).setVisible([
        'personal',
        'shared',
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('calendars.visible_ids'), [
        'personal',
        'shared',
      ]);
    });

    test('再起動後も保存済みの表示中カレンダー集合を復元する', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.visible_ids': ['personal', 'shared'],
      });

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      expect(visibleIds(container), ['personal', 'shared']);
    });

    test('単一 ID で保存していた頃（Issue #167）の値から移行する', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.selected_id': 'shared',
      });

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);

      expect(visibleIds(container), ['shared']);
    });

    test('退出済みのカレンダーは表示中集合から落とす', () async {
      SharedPreferences.setMockInitialValues({
        'calendars.visible_ids': ['personal', 'gone'],
      });

      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
      ]);

      expect(visibleIds(container), ['personal']);
    });

    test('上限を超えて表示しようとしても上限までで打ち切る', () async {
      final calendars = [
        for (var i = 0; i < kMaxVisibleCalendars + 2; i++)
          _calendar('cal-$i', 'カレンダー$i'),
      ];
      final container = await _containerWith(calendars);

      await container.read(calendarSelectionProvider.notifier).setVisible([
        for (final calendar in calendars) calendar.id,
      ]);

      expect(visibleIds(container), hasLength(kMaxVisibleCalendars));
    });

    test('上限に達していたら追加を無視する', () {
      final full = [for (var i = 0; i < kMaxVisibleCalendars; i++) 'cal-$i'];
      expect(canAddVisibleCalendar(full), isFalse);

      expect(toggledVisibleCalendarIds(full, 'cal-new'), full);
    });

    test('最後の 1 件は外せない（全非表示を作らせない）', () {
      expect(toggledVisibleCalendarIds(['personal'], 'personal'), ['personal']);
    });

    test('表示 ON/OFF を切り替えられる', () {
      expect(toggledVisibleCalendarIds(['personal'], 'shared'), [
        'personal',
        'shared',
      ]);
      expect(toggledVisibleCalendarIds(['personal', 'shared'], 'shared'), [
        'personal',
      ]);
    });

    test('フォールバックで表示中のカレンダーは追加操作で消えない', () async {
      // 未選択（保存値が空）でも先頭 1 件が表示される。その状態で別カレンダーを
      // 追加したとき、表示中だった先頭が黙って消えないこと。
      final container = await _containerWith([
        _calendar('personal', 'わたしのカレンダー'),
        _calendar('shared', '共有カレンダー'),
      ]);
      expect(visibleIds(container), ['personal']);

      await container
          .read(calendarSelectionProvider.notifier)
          .setVisible(
            toggledVisibleCalendarIds(visibleIds(container), 'shared'),
          );

      expect(visibleIds(container), ['personal', 'shared']);
    });
  });
}

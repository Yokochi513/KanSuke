import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/calendars/presentation/calendar_switcher.dart';
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

Future<ProviderContainer> _container(List<Calendar> calendars) async {
  final container = ProviderContainer(
    overrides: [
      myCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(myCalendarsProvider, (_, _) {});
  await container.read(myCalendarsProvider.future);
  await container.read(calendarSelectionProvider.future);
  return container;
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        appBar: null,
        body: Center(child: CalendarSwitcherTitle()),
      ),
    ),
  );
}

/// 切替シートを開く。
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byType(InkWell));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('複数のカレンダーをチェックで選べる（Issue #170）', (tester) async {
    final container = await _container([
      _calendar('personal', 'かぞく'),
      _calendar('shared', 'しごと'),
    ]);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _openSheet(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'しごと'));
    await tester.pumpAndSettle();

    expect(container.read(visibleCalendarIdsProvider), ['personal', 'shared']);
  });

  testWidgets('タイトルは複数表示中なら「先頭 ほかN件」になる（Issue #170）', (tester) async {
    final container = await _container([
      _calendar('personal', 'かぞく'),
      _calendar('shared', 'しごと'),
    ]);
    await container.read(calendarSelectionProvider.notifier).setVisible([
      'personal',
      'shared',
    ]);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('かぞく ほか1件'), findsOneWidget);
  });

  testWidgets('上限に達したら未選択のカレンダーは選べない（Issue #170）', (tester) async {
    final calendars = [
      for (var i = 0; i < kMaxVisibleCalendars + 1; i++)
        _calendar('cal-$i', 'カレンダー$i'),
    ];
    final container = await _container(calendars);
    await container.read(calendarSelectionProvider.notifier).setVisible([
      for (var i = 0; i < kMaxVisibleCalendars; i++) 'cal-$i',
    ]);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _openSheet(tester);

    // 上限超過は UI で防ぐ: 未選択の行は無効化し、理由も明示する。
    final overflowTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'カレンダー$kMaxVisibleCalendars'),
    );
    expect(overflowTile.onChanged, isNull);
    expect(find.textContaining('同時に表示できるのは'), findsOneWidget);
  });

  testWidgets('最後の 1 件はチェックを外せない（Issue #170）', (tester) async {
    final container = await _container([_calendar('personal', 'かぞく')]);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _openSheet(tester);

    final onlyTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'かぞく'),
    );
    expect(onlyTile.value, isTrue);
    expect(onlyTile.onChanged, isNull);
  });
}

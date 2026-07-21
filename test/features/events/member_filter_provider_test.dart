import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/events/application/event_filter.dart';
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

/// 参加カレンダーが 2 つある状態のコンテナ（表示中カレンダーの既定は先頭の `first`）。
Future<ProviderContainer> _containerWithCalendars() async {
  final container = ProviderContainer(
    overrides: [
      myCalendarsProvider.overrideWith(
        (ref) => Stream.value([
          _calendar('first', 'ひとつめ'),
          _calendar('second', 'ふたつめ'),
        ]),
      ),
    ],
  );
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

  test('toggle で選択と解除を切り替える', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(memberFilterProvider.notifier);

    expect(container.read(memberFilterProvider), isEmpty);
    notifier.toggle('papa');
    expect(container.read(memberFilterProvider), {'papa'});
    notifier.toggle('mama');
    expect(container.read(memberFilterProvider), {'papa', 'mama'});
    notifier.toggle('papa');
    expect(container.read(memberFilterProvider), {'mama'});
  });

  test('clear で全件表示へ戻す', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(memberFilterProvider.notifier);

    notifier.toggle('papa');
    notifier.clear();
    expect(container.read(memberFilterProvider), isEmpty);
  });

  test('カレンダー切替でフィルタがリセットされる（Issue #78）', () async {
    final container = await _containerWithCalendars();
    addTearDown(container.dispose);

    container.read(memberFilterProvider.notifier).toggle('papa');
    expect(container.read(memberFilterProvider), {'papa'});

    // 別カレンダーへ切り替えると、絞り込みは自動で解除される（build 中の状態変更を
    // 避けるため、リセットはマイクロタスクで反映される）。
    await container.read(calendarSelectionProvider.notifier).select('second');
    expect(container.read(selectedCalendarIdProvider), 'second');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(memberFilterProvider), isEmpty);
  });

  test('同じカレンダーのままなら選択は保持される', () async {
    final container = await _containerWithCalendars();
    addTearDown(container.dispose);

    container.read(memberFilterProvider.notifier).toggle('papa');
    // 表示中のカレンダー（先頭）を選び直しても値は変わらないのでリセットされない。
    await container.read(calendarSelectionProvider.notifier).select('first');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(memberFilterProvider), {'papa'});
  });
}

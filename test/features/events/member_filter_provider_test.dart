import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/events/application/event_filter.dart';
import 'package:kansuke/models/models.dart';

void main() {
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

  test('カレンダー切替でフィルタがリセットされる（Issue #78）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(memberFilterProvider.notifier).toggle('papa');
    expect(container.read(memberFilterProvider), {'papa'});

    // 別カレンダーへ切り替えると、絞り込みは自動で解除される。
    container.read(selectedCalendarIdProvider.notifier).state = 'other';
    expect(container.read(memberFilterProvider), isEmpty);
  });

  test('同じカレンダーのままなら選択は保持される', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(memberFilterProvider.notifier).toggle('papa');
    // 既定カレンダーのまま再設定しても値は変わらないのでリセットされない。
    container.read(selectedCalendarIdProvider.notifier).state =
        defaultCalendarId;
    expect(container.read(memberFilterProvider), {'papa'});
  });
}

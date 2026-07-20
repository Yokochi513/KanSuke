import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/settings/application/multi_member_display_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未保存・未知の値は既定（色分け）として扱う', () {
    expect(
      multiMemberEventDisplayFromName(null),
      MultiMemberEventDisplay.split,
    );
    expect(multiMemberEventDisplayFromName(''), MultiMemberEventDisplay.split);
    expect(
      multiMemberEventDisplayFromName('stripe'),
      MultiMemberEventDisplay.split,
    );
    expect(
      multiMemberEventDisplayFromName('split'),
      MultiMemberEventDisplay.split,
    );
    expect(
      multiMemberEventDisplayFromName('dots'),
      MultiMemberEventDisplay.dots,
    );
  });

  test('保存済みの表示方法を読み込む', () async {
    SharedPreferences.setMockInitialValues({
      'settings.multi_member_event_display': 'dots',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(multiMemberEventDisplayProvider.future),
      MultiMemberEventDisplay.dots,
    );
    expect(
      container.read(resolvedMultiMemberEventDisplayProvider),
      MultiMemberEventDisplay.dots,
    );
  });

  test('選択した表示方法を保存する', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(multiMemberEventDisplayProvider.future);

    await container
        .read(multiMemberEventDisplayProvider.notifier)
        .select(MultiMemberEventDisplay.dots);

    expect(
      container.read(resolvedMultiMemberEventDisplayProvider),
      MultiMemberEventDisplay.dots,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.multi_member_event_display'), 'dots');
  });

  test('読み込み中は既定（色分け）に従う', () {
    SharedPreferences.setMockInitialValues({
      'settings.multi_member_event_display': 'dots',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // await せずに読むと build() は未完了なので、既定値へ落ちる。
    expect(
      container.read(resolvedMultiMemberEventDisplayProvider),
      MultiMemberEventDisplay.split,
    );
  });
}

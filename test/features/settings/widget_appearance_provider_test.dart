import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/settings/application/widget_appearance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未保存・未知の値は端末設定に従う', () {
    expect(widgetAppearanceFromName(null), WidgetAppearance.system);
    expect(widgetAppearanceFromName(''), WidgetAppearance.system);
    expect(widgetAppearanceFromName('sepia'), WidgetAppearance.system);
    expect(widgetAppearanceFromName('light'), WidgetAppearance.light);
    expect(widgetAppearanceFromName('dark'), WidgetAppearance.dark);
    expect(
      widgetAppearanceFromName('transparent'),
      WidgetAppearance.transparent,
    );
  });

  test('保存済みの外観を読み込む', () async {
    SharedPreferences.setMockInitialValues({
      'settings.widget_appearance': 'transparent',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(widgetAppearanceProvider.future),
      WidgetAppearance.transparent,
    );
    expect(
      container.read(resolvedWidgetAppearanceProvider),
      WidgetAppearance.transparent,
    );
  });

  test('選択した外観を保存する', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(widgetAppearanceProvider.future);

    await container
        .read(widgetAppearanceProvider.notifier)
        .select(WidgetAppearance.dark);

    expect(
      container.read(resolvedWidgetAppearanceProvider),
      WidgetAppearance.dark,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.widget_appearance'), 'dark');
  });

  test('読み込み中は端末設定に従う', () {
    SharedPreferences.setMockInitialValues({
      'settings.widget_appearance': 'dark',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // await せずに読むと build() は未完了なので、既定値へ落ちる。
    expect(
      container.read(resolvedWidgetAppearanceProvider),
      WidgetAppearance.system,
    );
  });

  test('ペイロードへ載せる名前は Android 側の WidgetAppearance と揃える', () {
    // Kotlin 側 WidgetAppearance.key と 1 対 1 に対応させる。
    expect(WidgetAppearance.values.map((value) => value.name), [
      'system',
      'light',
      'dark',
      'transparent',
    ]);
  });
}

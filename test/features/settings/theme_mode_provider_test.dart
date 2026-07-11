import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/settings/application/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未保存・未知の値は端末設定に従う', () {
    expect(themeModeFromName(null), ThemeMode.system);
    expect(themeModeFromName(''), ThemeMode.system);
    expect(themeModeFromName('sepia'), ThemeMode.system);
    expect(themeModeFromName('dark'), ThemeMode.dark);
    expect(themeModeFromName('light'), ThemeMode.light);
  });

  test('保存済みのテーマを読み込む', () async {
    SharedPreferences.setMockInitialValues({'settings.theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(themeModeProvider.future), ThemeMode.dark);
    expect(container.read(resolvedThemeModeProvider), ThemeMode.dark);
  });

  test('選択したテーマを保存する', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeProvider.future);

    await container.read(themeModeProvider.notifier).select(ThemeMode.light);

    expect(container.read(resolvedThemeModeProvider), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.theme_mode'), 'light');
  });

  test('読み込み中は端末設定に従う', () {
    SharedPreferences.setMockInitialValues({'settings.theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // await せずに読むと build() は未完了なので、既定値へ落ちる。
    expect(container.read(resolvedThemeModeProvider), ThemeMode.system);
  });
}

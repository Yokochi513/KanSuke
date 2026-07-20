import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/settings/application/merged_bar_color_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未保存ならテーマ既定（null）として扱う', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(mergedBarColorProvider.future), isNull);
    expect(container.read(resolvedMergedBarColorProvider), isNull);
  });

  test('保存済みの帯色を読み込んで Color に解決する', () async {
    SharedPreferences.setMockInitialValues({
      'settings.merged_bar_color': '#BDB9AE',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(mergedBarColorProvider.future), '#BDB9AE');
    expect(
      container.read(resolvedMergedBarColorProvider),
      const Color(0xFFBDB9AE),
    );
  });

  test('選んだ帯色を保存する', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(mergedBarColorProvider.future);

    await container.read(mergedBarColorProvider.notifier).select('#D9C2C6');

    expect(
      container.read(resolvedMergedBarColorProvider),
      const Color(0xFFD9C2C6),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.merged_bar_color'), '#D9C2C6');
  });

  test('null を選ぶと保存を消してテーマ既定へ戻す', () async {
    SharedPreferences.setMockInitialValues({
      'settings.merged_bar_color': '#BDB9AE',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(mergedBarColorProvider.future);

    await container.read(mergedBarColorProvider.notifier).select(null);

    expect(container.read(resolvedMergedBarColorProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.merged_bar_color'), isNull);
  });

  test('読み込み中はテーマ既定（null）に従う', () {
    SharedPreferences.setMockInitialValues({
      'settings.merged_bar_color': '#BDB9AE',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // await せずに読むと build() は未完了なので、既定（null）へ落ちる。
    expect(container.read(resolvedMergedBarColorProvider), isNull);
  });
}

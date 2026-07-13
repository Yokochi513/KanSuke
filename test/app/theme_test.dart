import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/theme.dart';

void main() {
  test('ライトテーマは和紙の地と紺の基調色を持つ', () {
    final theme = buildKanSukeTheme();

    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, WashiColors.kon);
    expect(theme.colorScheme.surface, WashiColors.kinari);
    expect(theme.extension<KanSukeColors>(), KanSukeColors.light);
  });

  test('ダークテーマは墨の地と藍白の基調色を持つ', () {
    final theme = buildKanSukeDarkTheme();

    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, WashiColors.aijiro);
    expect(theme.colorScheme.surface, WashiColors.sumi);
    expect(theme.extension<KanSukeColors>(), KanSukeColors.dark);
  });

  test('和紙テクスチャを透かすため Scaffold の地は透過させる', () {
    expect(buildKanSukeTheme().scaffoldBackgroundColor, Colors.transparent);
    expect(buildKanSukeDarkTheme().scaffoldBackgroundColor, Colors.transparent);
  });

  test('メンバー識別色は 6 色で、すべて異なる', () {
    expect(MemberColors.palette, hasLength(6));
    expect(
      MemberColors.palette.map((color) => color.toARGB32()).toSet(),
      hasLength(6),
    );
  });

  testWidgets('テーマ未登録でも KanSukeColors.of はライトの既定値へ落ちる', (tester) async {
    late KanSukeColors resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = KanSukeColors.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, KanSukeColors.light);
  });
}

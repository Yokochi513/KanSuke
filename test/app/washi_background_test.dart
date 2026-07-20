import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/theme.dart';
import 'package:kansuke/app/washi_background.dart';

void main() {
  // Issue #124: 各ルートを WashiBackground で包むことでページ遷移中の画面崩れを防ぐ。
  // その前提として、WashiBackground が「不透明な」和紙の地色で覆っていることを担保する。
  // ここが透過してしまうと、戻る操作の遷移中に手前と背後の画面が重なって見えてしまう。
  testWidgets('WashiBackground は不透明な和紙の地色で子を覆う', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKanSukeTheme(),
        home: const WashiBackground(child: SizedBox.shrink()),
      ),
    );

    final coloredBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(WashiBackground),
        matching: find.byType(ColoredBox),
      ),
    );

    expect(coloredBox.color, KanSukeColors.light.washiBase);
    // アルファが最大（不透明）であること。ここが透けると Issue #124 が再発する。
    expect(coloredBox.color.a, 1.0);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendar/presentation/calendar_screen.dart';
import 'package:kansuke/models/models.dart';

/// Issue #125: 月表示のマージ帯（[MergedEventBar]）で、タイトルチップの右端が
/// 日別ドット（〇）の途中に掛かると、欠けた〇がタイトル脇にはみ出して文字と
/// 重なって見える。チップに一部でも掛かる〇は描かないことを検証する。
///
/// テストフォントは 1 グリフ＝fontSize（11px）幅なので、タイトル「夏休み」の
/// 幅は 33px、チップ右端は左パディング 2 ＋チップ内パディング 2×2 ＋ 33 = 39px。
void main() {
  const blue = Color(0xFF1565C0);
  const red = Color(0xFFD84315);

  Widget harness({required double width, required MergedEventBar bar}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: 16, child: bar),
        ),
      ),
    );
  }

  Finder dotFinder() {
    return find.descendant(
      of: find.byType(MergedEventBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
  }

  testWidgets('タイトルチップに掛かる〇は描かない（Issue #125）', (tester) async {
    // 2 日分で幅 140px（1 日 70px）。1 日目の〇 2 個は中央寄せで左端 22px・
    // 36px に置かれ、どちらもチップ右端（39px）に掛かるため描かれない。
    // 2 日目の〇（92px・106px）はチップより右なので描かれる。
    await tester.pumpWidget(
      harness(
        width: 140,
        bar: const MergedEventBar(
          title: '夏休み',
          dayColors: [
            [blue, red],
            [blue, red],
          ],
          type: EventType.confirmed,
        ),
      ),
    );

    expect(dotFinder(), findsNWidgets(2));

    // 描かれた〇はすべてタイトル文字の右端より右にあり、文字と重ならない。
    final titleRight = tester.getBottomRight(find.text('夏休み')).dx;
    for (final element in dotFinder().evaluate()) {
      final dotLeft = tester.getTopLeft(find.byWidget(element.widget)).dx;
      expect(dotLeft, greaterThanOrEqualTo(titleRight));
    }
  });

  testWidgets('チップに掛からない〇はすべて描く（Issue #125）', (tester) async {
    // 幅 600px（1 日 300px）なら 1 日目の〇（左端 137px〜）もチップ右端
    // （39px）より右にあり、全 4 個が描かれる。
    await tester.pumpWidget(
      harness(
        width: 600,
        bar: const MergedEventBar(
          title: '夏休み',
          dayColors: [
            [blue, red],
            [blue, red],
          ],
          type: EventType.confirmed,
        ),
      ),
    );

    expect(dotFinder(), findsNWidgets(4));
  });
}

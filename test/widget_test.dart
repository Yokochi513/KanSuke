import 'package:flutter_test/flutter_test.dart';

import 'package:kansuke/main.dart';

void main() {
  testWidgets('KanSukeのプレースホルダ画面を表示する', (tester) async {
    await tester.pumpWidget(const KanSukeApp());

    expect(find.text('KanSuke'), findsNWidgets(2));
  });
}

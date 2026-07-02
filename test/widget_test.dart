import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/app.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';

void main() {
  testWidgets('認証状態に応じてサインインからカレンダーへ切り替わる', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KanSukeApp()));

    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('仮ログイン'), findsOneWidget);

    await tester.tap(find.text('仮ログイン'));
    await tester.pumpAndSettle();

    expect(find.text('カレンダー'), findsOneWidget);
    expect(find.text('サインイン'), findsNothing);
  });

  testWidgets('ログイン済みならカレンダー画面と各プレースホルダへ遷移できる', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(SignedInAuthStateNotifier.new),
        ],
        child: const KanSukeApp(),
      ),
    );

    expect(find.text('カレンダー'), findsOneWidget);

    await tester.tap(find.text('日別予定一覧'));
    await tester.pumpAndSettle();
    expect(find.text('選択日の予定を表示します'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('予定を編集'));
    await tester.pumpAndSettle();
    expect(find.text('予定を作成・編集します'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
  });
}

class SignedInAuthStateNotifier extends AuthStateNotifier {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

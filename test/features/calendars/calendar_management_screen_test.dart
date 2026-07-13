import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendars/presentation/calendar_edit_args.dart';
import 'package:kansuke/features/calendars/presentation/calendar_management_screen.dart';
import 'package:kansuke/features/invites/application/invite_providers.dart';

/// テスト用のカレンダー ID（本番の ID は UUID。特別扱いされる固定 ID は無い）。
const testCalendarId = 'test-calendar';

Future<FakeFirebaseFirestore> _seed() async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(testCalendarId).set({
    'name': 'わが家',
    'memberIds': ['me', 'other'],
    'creatorId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  await firestore.collection('calendars').doc('other-only').set({
    'name': '参加していないカレンダー',
    'memberIds': ['other'],
    'creatorId': 'other',
    'createdAt': now,
    'updatedAt': now,
  });
  return firestore;
}

Widget _wrap(FakeFirebaseFirestore firestore, {List<Object?>? editArgsSink}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
    ],
    child: MaterialApp(
      home: const CalendarManagementScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.calendarEdit) {
          editArgsSink?.add(settings.arguments);
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('EDIT_SCREEN')),
          );
        }
        return null;
      },
    ),
  );
}

void main() {
  testWidgets('自分が参加しているカレンダーだけを一覧表示する', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    expect(find.text('わが家'), findsOneWidget);
    expect(find.text('参加していないカレンダー'), findsNothing);
  });

  testWidgets('カレンダーをタップすると編集画面へ既存カレンダーを渡して遷移する', (tester) async {
    final firestore = await _seed();
    final sink = <Object?>[];
    await tester.pumpWidget(_wrap(firestore, editArgsSink: sink));
    await tester.pumpAndSettle();

    await tester.tap(find.text('わが家'));
    await tester.pumpAndSettle();

    expect(find.text('EDIT_SCREEN'), findsOneWidget);
    expect(sink.single, isA<CalendarEditArgs>());
    expect((sink.single as CalendarEditArgs).isCreate, isFalse);
  });

  testWidgets('招待リンクを貼り付けると受諾待ちのトークンになる（FR-9 / Issue #90）', (tester) async {
    // Web ではカスタムスキームのリンクを踏めないため、貼り付けが参加の受け口になる。
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(await _seed()),
        currentUidProvider.overrideWithValue('me'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CalendarManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('招待リンクで参加'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'kansuke://invite?token=token-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(container.read(pendingInviteTokenProvider), 'token-1');
  });

  testWidgets('貼り付けが招待リンクでなければエラーを出す', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('招待リンクで参加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'https://example.com/');
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(find.text('招待リンクを正しく貼り付けてください'), findsOneWidget);
  });

  testWidgets('新規作成ボタンで作成用の編集画面を開く', (tester) async {
    final firestore = await _seed();
    final sink = <Object?>[];
    await tester.pumpWidget(_wrap(firestore, editArgsSink: sink));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    expect(find.text('EDIT_SCREEN'), findsOneWidget);
    expect((sink.single as CalendarEditArgs).isCreate, isTrue);
  });
}

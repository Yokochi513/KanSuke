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
import 'package:shared_preferences/shared_preferences.dart';

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
  await firestore.collection('calendars').doc('second-calendar').set({
    'name': 'わが家より後ろ',
    'memberIds': ['me'],
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
  // 並び順（Issue #168）は端末ローカルに保存する。
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ドラッグで並べ替えると順序が端末ローカルに保存される（Issue #168）', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // 2 件目のハンドルを掴んで先頭へ移動する。
    final handle = find.byIcon(Icons.drag_handle).at(1);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('calendars.order'), [
      'second-calendar',
      testCalendarId,
    ]);
  });

  testWidgets('保存済みの並び順で一覧を表示する（Issue #168）', (tester) async {
    SharedPreferences.setMockInitialValues({
      'calendars.order': ['second-calendar', testCalendarId],
    });
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['わが家より後ろ', 'わが家']);
  });

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

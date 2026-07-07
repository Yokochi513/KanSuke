import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendar/presentation/calendar_screen.dart';
import 'package:kansuke/models/models.dart';
import 'package:table_calendar/table_calendar.dart';

Future<FakeFirebaseFirestore> _seed({required DateTime today}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  final start = DateTime(today.year, today.month, today.day, 9);
  final event = Event.create(
    title: '会議',
    creatorId: 'me',
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const [60],
    updatedBy: 'me',
    now: start,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
  return firestore;
}

/// 同じ日に複数メンバー・多数の予定を投入する（マス目表示の検証用）。
Future<FakeFirebaseFirestore> _seedManyOnOneDay({
  required DateTime today,
}) async {
  final firestore = FakeFirebaseFirestore();
  for (final (id, name, color) in const [
    ('me', 'ぱぱ', '#1565C0'),
    ('mama', 'まま', '#D84315'),
  ]) {
    await firestore.collection('users').doc(id).set({
      'name': name,
      'email': '$id@example.com',
      'color': color,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }
  // 1 マスに収まりきらない本数を同日に作る（「+N」省略を発生させる）。
  for (var i = 0; i < 8; i++) {
    final start = DateTime(today.year, today.month, today.day, 8 + i);
    final creator = i.isEven ? 'me' : 'mama';
    final event = Event.create(
      title: '予定${i + 1}',
      creatorId: creator,
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: i.isEven ? EventType.confirmed : EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: creator,
      now: start,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

Widget _wrap(FakeFirebaseFirestore firestore, {DateTime? initialFocusedDay}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
    ],
    child: MaterialApp(
      home: CalendarScreen(initialFocusedDay: initialFocusedDay),
      routes: {
        AppRoutes.dayEvents: (_) =>
            const Scaffold(body: Text('DAY_LIST_SCREEN')),
        AppRoutes.settings: (_) => const Scaffold(body: Text('SETTINGS')),
      },
    ),
  );
}

void main() {
  testWidgets('月表示と凡例を描画する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    expect(find.byType(TableCalendar<Event>), findsOneWidget);
    expect(find.text('ぱぱ'), findsOneWidget); // 凡例
  });

  testWidgets('祝日は日曜日と同じ赤字・セル色なしで祝日名を表示する', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    final holidayDayText = tester.widget<Text>(find.text('15').first);

    expect(holidayDayText.style?.color, Colors.red.shade400);
    expect(find.text('海の日'), findsOneWidget);
    expect(find.byTooltip('海の日'), findsOneWidget);
  });

  testWidgets('日付のシングルタップでは遷移しない', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();

    // 誤操作防止のため、シングルタップは選択のみで遷移しない。
    expect(find.text('DAY_LIST_SCREEN'), findsNothing);
  });

  testWidgets('日付のダブルタップで日別一覧へ遷移する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // 同じ日を短時間に 2 回タップする（自前ダブルタップ判定）。
    await tester.tap(find.text('${today.day}').first);
    await tester.pump();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('DAY_LIST_SCREEN'), findsOneWidget);
  });

  testWidgets('同日に複数予定があるとマスにバーと「+N」を表示する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seedManyOnOneDay(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // マス目に予定バー（タイトル）が並ぶ。
    expect(find.byType(EventBar), findsWidgets);
    expect(find.text('予定1'), findsOneWidget);
    // マスに収まらない分は「+N」で省略される（オーバーフローしない）。
    expect(find.textContaining('+'), findsWidgets);
  });

  testWidgets('EventBar は確定=塗り・仮=枠付きで種別を区別する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EventBar(
                title: '会議',
                colors: [Color(0xFF1565C0)],
                type: EventType.confirmed,
              ),
              EventBar(
                title: '会議',
                colors: [Color(0xFF1565C0)],
                type: EventType.tentative,
              ),
            ],
          ),
        ),
      ),
    );

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .toList();
    final confirmed = decorations[0];
    final tentative = decorations[1];

    expect(confirmed.border, isNull);
    expect(tentative.border, isNotNull);
  });

  testWidgets('EventBarは参加メンバー数だけ色を分割して表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventBar(
            title: '家族会議',
            colors: [Color(0xFF1565C0), Color(0xFFD84315), Color(0xFF2E7D32)],
            type: EventType.confirmed,
          ),
        ),
      ),
    );

    final segments = tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(EventBar),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((box) => box.color)
        .toList();

    expect(segments, [
      const Color(0xFF1565C0),
      const Color(0xFFD84315),
      const Color(0xFF2E7D32),
    ]);
  });

  testWidgets('ヘッダの年月タップでホイールピッカーを表示し、月を選ぶとその月へ飛ぶ', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024年7月'));
    await tester.pumpAndSettle();

    // 「年」「月」それぞれのホイールピッカーが表示される。
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    expect(find.text('完了'), findsOneWidget);

    // 月ホイールを 1 目盛り分ドラッグして選択を進める（7月→8月）。
    await tester.drag(find.byType(CupertinoPicker).last, const Offset(0, -40));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    // 選んだ月へフォーカスが移り、ヘッダのタイトルが更新される。
    expect(find.text('2024年8月'), findsOneWidget);
  });

  testWidgets('ホイールピッカーで年を切り替えられる', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024年7月'));
    await tester.pumpAndSettle();

    // 年ホイールを 1 目盛り分ドラッグして選択を進める（2024年→2025年）。
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -40));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.text('2025年7月'), findsOneWidget);
  });

  testWidgets('ホイールピッカーでキャンセルすると月が変わらない', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024年7月'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CupertinoPicker).last, const Offset(0, -40));
    await tester.pumpAndSettle();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('2024年7月'), findsOneWidget);
  });

  testWidgets('参加者がいる予定はマス目のバーもメンバー数だけ分割される', (tester) async {
    final today = DateTime.now();
    final firestore = FakeFirebaseFirestore();
    for (final (id, name, color) in const [
      ('me', 'ぱぱ', '#1565C0'),
      ('mama', 'まま', '#D84315'),
    ]) {
      await firestore.collection('users').doc(id).set({
        'name': name,
        'email': '$id@example.com',
        'color': color,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });
    }
    final start = DateTime(today.year, today.month, today.day, 9);
    final sharedEvent = Event.create(
      title: '家族の予定',
      creatorId: 'me',
      participantIds: const ['me', 'mama'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
    );
    await firestore
        .collection('events')
        .doc(sharedEvent.id)
        .set(sharedEvent.toFirestore(useServerTimestamp: false));

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    final bar = tester.widget<EventBar>(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == '家族の予定',
      ),
    );

    expect(bar.colors, [const Color(0xFF1565C0), const Color(0xFFD84315)]);
  });
}

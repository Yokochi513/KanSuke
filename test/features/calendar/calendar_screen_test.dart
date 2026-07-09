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
      participantIds: [creator],
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

Future<FakeFirebaseFirestore> _seedCurrentUserPriority({
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
  for (final (title, participantId, hour) in [
    ('他人の朝予定', 'mama', 8),
    ('自分の夜予定', 'me', 20),
  ]) {
    final start = DateTime(today.year, today.month, today.day, hour);
    final event = Event.create(
      title: title,
      creatorId: participantId,
      participantIds: [participantId],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const [],
      updatedBy: participantId,
      now: start,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

Future<FakeFirebaseFirestore> _seedPeriodEvent() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  final start = DateTime(2026, 7, 5, 9);
  final event = Event.create(
    title: 'テスト週間',
    creatorId: 'me',
    startAt: start,
    endAt: DateTime(2026, 7, 7, 10),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const [],
    updatedBy: 'me',
    now: start,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
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

  testWidgets('選択済みの日付を再タップすると日別一覧へ遷移する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // Issue #45: 時間制限つきダブルタップではなく、選択済み日付への
    // 明示的な 2 回目タップで日別一覧へ移動する。
    await tester.tap(find.text('${today.day}').first);
    await tester.pump(const Duration(seconds: 1));
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

  testWidgets('月表示では自分が参加者の予定を同日の先頭に表示する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seedCurrentUserPriority(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<EventBar>(find.byType(EventBar))
        .map((bar) => bar.title)
        .toList();

    expect(titles.take(2), ['自分の夜予定', '他人の朝予定']);
  });

  testWidgets('期間予定は重なる各日のマスにバーを表示するが、タイトルは週内の最初の日のみ表示する', (tester) async {
    final firestore = await _seedPeriodEvent();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    // バー自体は 3 日分（7/5〜7/7）描画されるが、毎日同じ名前が並ぶと
    // 煩わしいため、タイトル文字は週内で最初に現れる日（7/5）にのみ表示する。
    expect(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == 'テスト週間',
      ),
      findsNWidgets(3),
    );
    expect(find.text('テスト週間'), findsOneWidget);
  });

  testWidgets('期間予定は開始日・終了日以外の角丸/枠線を外して連結して見える（Issue #56）', (tester) async {
    // 2026/7/5(日)〜7/7(火) は同じ週（行）内に収まるため、中日は
    // 左右とも角丸なし、開始日は左のみ・終了日は右のみ角丸になるはず。
    final firestore = await _seedPeriodEvent();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bars = tester
        .widgetList<EventBar>(
          find.byWidgetPredicate(
            (widget) => widget is EventBar && widget.title == 'テスト週間',
          ),
        )
        .toList();

    expect(bars, hasLength(3));
    // 開始日（7/5）：左端は実際の開始日として角丸、右は翌日へ連結するため角丸なし。
    // 週内で最初に現れる日でもあるためタイトルも表示する。
    expect(bars[0].roundLeft, isTrue);
    expect(bars[0].roundRight, isFalse);
    expect(bars[0].showTitle, isTrue);
    // 中日（7/6）：前後どちらにも連結するため両側とも角丸なし、タイトルも非表示。
    expect(bars[1].roundLeft, isFalse);
    expect(bars[1].roundRight, isFalse);
    expect(bars[1].showTitle, isFalse);
    // 終了日（7/7）：右端は実際の終了日として角丸、左は前日から連結するため角丸なし。
    // タイトルは既に表示済みのため非表示。
    expect(bars[2].roundLeft, isFalse);
    expect(bars[2].roundRight, isTrue);
    expect(bars[2].showTitle, isFalse);
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

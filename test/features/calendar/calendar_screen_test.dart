import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/app/theme.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendar/presentation/calendar_screen.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/events/presentation/event_type_badge.dart';
import 'package:kansuke/features/settings/application/event_merge_provider.dart';
import 'package:kansuke/features/settings/application/multi_member_display_provider.dart';
import 'package:kansuke/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

/// テスト用のカレンダー ID（本番の ID は UUID。特別扱いされる固定 ID は無い）。
const testCalendarId = 'test-calendar';

/// users は列挙禁止（Issue #89）。メンバーの色・名前は参加カレンダーの memberIds
/// から引くため、me と mama が参加する既定カレンダーを用意する（FR-8）。
Future<FakeFirebaseFirestore> _firestoreWithCalendar() async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(testCalendarId).set({
    'name': 'わが家',
    'memberIds': ['me', 'mama'],
    'creatorId': 'me',
    'ownerId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  return firestore;
}

/// 2 つのカレンダー（A: me+mama / B: me+kids）と 3 名のユーザーを用意する。
/// Issue #130: カレンダー切替で凡例が選択中カレンダーの参加者に切り替わることの検証用。
Future<FakeFirebaseFirestore> _firestoreWithTwoCalendars() async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  for (final (id, name, memberIds) in const [
    ('cal-a', 'カレンダーA', ['me', 'mama']),
    ('cal-b', 'カレンダーB', ['me', 'kids']),
  ]) {
    await firestore.collection('calendars').doc(id).set({
      'name': name,
      'memberIds': memberIds,
      'creatorId': 'me',
      'ownerId': 'me',
      'createdAt': now,
      'updatedAt': now,
    });
  }
  for (final (id, name, color) in const [
    ('me', 'ぱぱ', '#1565C0'),
    ('mama', 'まま', '#D84315'),
    ('kids', 'きっず', '#2E7D32'),
  ]) {
    await firestore.collection('users').doc(id).set({
      'name': name,
      'email': '$id@example.com',
      'color': color,
      'createdAt': now,
      'updatedAt': now,
    });
  }
  return firestore;
}

Future<FakeFirebaseFirestore> _seed({required DateTime today}) async {
  final firestore = await _firestoreWithCalendar();
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
    reminderOffsets: const {
      'me': [60],
    },
    updatedBy: 'me',
    now: start,
    calendarId: testCalendarId,
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
  final firestore = await _firestoreWithCalendar();
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
      reminderOffsets: const {},
      updatedBy: creator,
      now: start,
      calendarId: testCalendarId,
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
  final firestore = await _firestoreWithCalendar();
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
      reminderOffsets: const {},
      updatedBy: participantId,
      now: start,
      calendarId: testCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

/// ぱぱ・まま 2 人が参加する予定を 1 件投入する（複数人表示の検証用）。
Future<FakeFirebaseFirestore> _seedSharedEvent({
  required DateTime today,
}) async {
  final firestore = await _firestoreWithCalendar();
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
    reminderOffsets: const {},
    updatedBy: 'me',
    now: start,
    calendarId: testCalendarId,
  );
  await firestore
      .collection('events')
      .doc(sharedEvent.id)
      .set(sharedEvent.toFirestore(useServerTimestamp: false));
  return firestore;
}

Future<FakeFirebaseFirestore> _seedPeriodEvent() async {
  final firestore = await _firestoreWithCalendar();
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
    reminderOffsets: const {},
    updatedBy: 'me',
    now: start,
    calendarId: testCalendarId,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
  return firestore;
}

/// 週（土→日）を跨ぐ期間予定を投入する（Issue #72 の連結表示検証用）。
Future<FakeFirebaseFirestore> _seedCrossWeekEvent() async {
  final firestore = await _firestoreWithCalendar();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  final event = Event.create(
    title: '週またぎ',
    creatorId: 'me',
    startAt: DateTime(2026, 7, 4, 9),
    endAt: DateTime(2026, 7, 6, 10),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const {},
    updatedBy: 'me',
    now: DateTime(2026, 7, 4, 9),
    calendarId: testCalendarId,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
  return firestore;
}

Future<FakeFirebaseFirestore> _seedAdjacentMonthEvents() async {
  final firestore = await _firestoreWithCalendar();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });

  for (final eventSeed in [
    (title: '前月末の予定', startAt: DateTime(2025, 12, 31, 9)),
    (title: '翌月初の予定', startAt: DateTime(2026, 2, 1, 9)),
  ]) {
    final event = Event.create(
      title: eventSeed.title,
      creatorId: 'me',
      startAt: eventSeed.startAt,
      endAt: eventSeed.startAt.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const {},
      updatedBy: 'me',
      now: eventSeed.startAt,
      calendarId: testCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

/// 同名で期間が連なる予定（マージ表示の検証用）。各 seed の (title, creator,
/// start, end, type) を投入する。
Future<FakeFirebaseFirestore> _seedTitledEvents(
  List<
    ({
      String title,
      String creator,
      DateTime start,
      DateTime end,
      EventType type,
    })
  >
  seeds,
) async {
  final firestore = await _firestoreWithCalendar();
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
  for (final seed in seeds) {
    final event = Event.create(
      title: seed.title,
      creatorId: seed.creator,
      participantIds: [seed.creator],
      startAt: seed.start,
      endAt: seed.end,
      allDay: false,
      type: seed.type,
      memo: '',
      reminderOffsets: const {},
      updatedBy: seed.creator,
      now: seed.start,
      calendarId: testCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

Widget _wrap(
  FakeFirebaseFirestore firestore, {
  DateTime? initialFocusedDay,
  bool mergeEnabled = true,
  // アプリの既定（色分け、Issue #112）に合わせる。
  MultiMemberEventDisplay multiMemberDisplay = MultiMemberEventDisplay.split,
}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
      resolvedEventMergeEnabledProvider.overrideWithValue(mergeEnabled),
      resolvedMultiMemberEventDisplayProvider.overrideWithValue(
        multiMemberDisplay,
      ),
      // 月表示の描画に集中するため、表示中カレンダーは固定する（カレンダーの
      // 解決自体は calendar_providers_test で検証する）。
      selectedCalendarIdProvider.overrideWithValue(testCalendarId),
    ],
    child: MaterialApp(
      theme: buildKanSukeTheme(),
      home: CalendarScreen(initialFocusedDay: initialFocusedDay),
      routes: {
        AppRoutes.dayEvents: (_) =>
            const Scaffold(body: Text('DAY_LIST_SCREEN')),
        AppRoutes.settings: (_) => const Scaffold(body: Text('SETTINGS')),
        AppRoutes.eventEdit: (_) =>
            const Scaffold(body: Text('EVENT_EDIT_SCREEN')),
      },
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('月表示と凡例を描画する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    expect(find.byType(TableCalendar<Event>), findsOneWidget);
    expect(find.text('ぱぱ'), findsOneWidget); // 凡例
  });

  testWidgets('祝日は日曜日と同じ朱色・セル色なしで祝日名を表示する', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    final holidayDayText = tester.widget<Text>(find.text('15').first);

    expect(holidayDayText.style?.color, KanSukeColors.light.holiday);
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

  testWidgets('横画面など行が低くても各日に最低1件は予定バーを表示する（Issue #126）', (tester) async {
    // 横画面相当の低い行高では、既定寸法だと日付の下に帯が 1 本も入らず
    // 「+N」だけになってしまう。圧縮表示へ切り替え、最低 1 件は帯を出す
    // （「帯が細くなってもいいから一つは情報がほしい」というフィードバック）。
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final firestore = await _seedManyOnOneDay(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // 低い行でも予定バーが最低 1 本は描かれる（従来は「+N」だけになっていた）。
    expect(find.byType(EventBar), findsWidgets);
    // 1 行しか入らない低い行では「+N」より帯 1 件を優先し、「+N」は出さない。
    expect(find.textContaining('+'), findsNothing);
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

  testWidgets('期間予定は週内で1本の連続バーとして描き、題名を全幅で表示する（Issue #72）', (tester) async {
    final firestore = await _seedPeriodEvent();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    // Issue #72: 7/5〜7/7 は同じ週に収まるため、日ごとに分割せず 1 本の帯として
    // 描く。題名は span 全幅を使って 1 回だけ表示する。
    final barFinder = find.byWidgetPredicate(
      (widget) => widget is EventBar && widget.title == 'テスト週間',
    );
    expect(barFinder, findsOneWidget);
    expect(find.text('テスト週間'), findsOneWidget);

    // 3 列（日〜火）にまたがるため、バー幅は 1 列幅（カレンダー幅 / 7）を
    // はるかに超える。オーバーレイの座標計算が崩れると検知できる。
    final calendarWidth = tester
        .getSize(find.byType(TableCalendar<Event>))
        .width;
    final barWidth = tester.getSize(barFinder).width;
    expect(barWidth, greaterThan(calendarWidth / 7 * 2));
  });

  testWidgets('週内に収まる期間予定は開始端・終了端とも角丸の1本のバーになる（Issue #72）', (tester) async {
    // 2026/7/5(日)〜7/7(火) は同じ週（行）内に収まるため、開始端・終了端とも
    // 角丸・枠線を付けた 1 本のバーとして描く。
    final firestore = await _seedPeriodEvent();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<EventBar>(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == 'テスト週間',
      ),
    );

    expect(bar.roundLeft, isTrue);
    expect(bar.roundRight, isTrue);
    expect(bar.showTitle, isTrue);
  });

  testWidgets('週をまたぐ期間予定は週ごとに分かれ、継続端の角丸を外す（Issue #72）', (tester) async {
    // 2026/7/4(土)〜7/6(月) は土→日で週（行）を跨ぐため、前の週と次の週で
    // 2 本に分かれる。跨ぎ目（週末・週頭）の角は落として連結して見せる。
    final firestore = await _seedCrossWeekEvent();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bars = tester
        .widgetList<EventBar>(
          find.byWidgetPredicate(
            (widget) => widget is EventBar && widget.title == '週またぎ',
          ),
        )
        .toList();

    expect(bars, hasLength(2));
    // 前の週（7/4・土）：開始端は角丸、週末側は次週へ連結するため角丸なし。
    expect(bars[0].roundLeft, isTrue);
    expect(bars[0].roundRight, isFalse);
    // 次の週（7/5〜7/6）：週頭側は前週から連結するため角丸なし、終了端は角丸。
    expect(bars[1].roundLeft, isFalse);
    expect(bars[1].roundRight, isTrue);
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

  testWidgets('仮の予定のタイトルは薄い識別色でも読める色で描く（Issue #106）', (tester) async {
    // 薄い水色（#81D4FA）は明るく、識別色をそのまま文字色にすると背景に
    // 埋もれて読めない。実効地色の明度から選んだ黒/白で描かれることを確かめる。
    const lightBlue = Color(0xFF81D4FA);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventBar(
            title: 'いゆはの予定',
            colors: [lightBlue],
            type: EventType.tentative,
          ),
        ),
      ),
    );

    final titleColor = tester.widget<Text>(find.text('いゆはの予定')).style!.color;
    expect(titleColor, isNot(lightBlue));
    expect(titleColor, Colors.black);
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

  testWidgets('EventBarの塗り分け帯は区画ごとに読める文字色でタイトルを描く（Issue #133）', (tester) async {
    // 濃紺（#1565C0）と薄い水色（#81D4FA）の 2 人帯。先頭色だけで文字色を
    // 決めると、水色の区画にまたがった文字が白のままで埋もれる。
    const navy = Color(0xFF1565C0);
    const lightBlue = Color(0xFF81D4FA);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventBar(
            title: '家族会議',
            colors: [navy, lightBlue],
            type: EventType.confirmed,
          ),
        ),
      ),
    );

    final titleColors = tester
        .widgetList<Text>(find.text('家族会議'))
        .map((text) => text.style!.color)
        .toList();

    // 区画数ぶんのタイトルが、それぞれの地色に合う色で描かれる。
    expect(titleColors, [Colors.white, Colors.black]);
  });

  testWidgets('EventBarの丸マーク表示は帯を塗り分けず参加者色の〇を描く（Issue #112）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventBar(
            title: 'ディズニー',
            colors: [Color(0xFF1565C0), Color(0xFFD84315), Color(0xFF2E7D32)],
            type: EventType.confirmed,
            memberDots: true,
          ),
        ),
      ),
    );

    // 帯は参加者色で塗り分けない（等分割の ColoredBox を作らない）。
    expect(
      find.descendant(
        of: find.byType(EventBar),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );

    // タイトルの右に参加者 3 人分の〇が色順どおりに並ぶ。
    final dotColors = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(EventBar),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.shape == BoxShape.circle)
        .map((decoration) => decoration.color)
        .toList();
    expect(dotColors, [
      const Color(0xFF1565C0),
      const Color(0xFFD84315),
      const Color(0xFF2E7D32),
    ]);
    expect(find.text('ディズニー'), findsOneWidget);
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

  testWidgets('左右スワイプでスライドして前後の月へ切り替わる（Issue #134）', (tester) async {
    final focusedDay = DateTime(2024, 7, 1);
    final firestore = await _seed(today: focusedDay);

    await tester.pumpWidget(_wrap(firestore, initialFocusedDay: focusedDay));
    await tester.pumpAndSettle();

    expect(find.text('2024年7月'), findsOneWidget);
    // グリッドとバーをまとめてスライドさせる AnimatedSwitcher が居る。
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    // 静止時はカレンダーページ（グリッド）が 1 枚だけ。
    expect(find.byType(TableCalendar<Event>), findsOneWidget);

    // 左へフリック → 翌月へ。遷移中は新旧 2 枚のグリッドがスライドで共存する
    // （瞬時の差し替えではなくアニメーションで切り替わっている証跡）。
    await tester.fling(
      find.byType(TableCalendar<Event>),
      const Offset(-300, 0),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(TableCalendar<Event>), findsNWidgets(2));
    await tester.pumpAndSettle();
    // スワイプ方向（左＝進む）と月の進退（翌月）が一致する。
    expect(find.text('2024年8月'), findsOneWidget);

    // 右へフリック → 前月へ戻る。
    await tester.fling(
      find.byType(TableCalendar<Event>),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('2024年7月'), findsOneWidget);
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

  testWidgets('「色分け」設定では参加者がいる予定のバーをメンバー数だけ分割する（Issue #112）', (tester) async {
    final today = DateTime.now();
    final firestore = await _seedSharedEvent(today: today);

    await tester.pumpWidget(
      _wrap(firestore, multiMemberDisplay: MultiMemberEventDisplay.split),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<EventBar>(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == '家族の予定',
      ),
    );

    expect(bar.colors, [const Color(0xFF1565C0), const Color(0xFFD84315)]);
    // 従来どおり塗り分けで描く（丸マークにしない）。
    expect(bar.memberDots, isFalse);
  });

  testWidgets('「丸マーク」設定では複数人の予定を塗り分けず参加者色の〇を並べる（Issue #112）', (tester) async {
    final today = DateTime.now();
    final firestore = await _seedSharedEvent(today: today);

    await tester.pumpWidget(
      _wrap(firestore, multiMemberDisplay: MultiMemberEventDisplay.dots),
    );
    await tester.pumpAndSettle();

    final barFinder = find.byWidgetPredicate(
      (widget) => widget is EventBar && widget.title == '家族の予定',
    );
    final bar = tester.widget<EventBar>(barFinder);
    expect(bar.memberDots, isTrue);
    // Issue #105 と同様、自分(me)が参加者なので地色を自分の色へ寄せる。
    expect(bar.selfColor, const Color(0xFF1565C0));

    // タイトルの右に参加者色の〇（ぱぱ＝青・まま＝橙）が並ぶ。
    final dotColors = tester
        .widgetList<Container>(
          find.descendant(of: barFinder, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.shape == BoxShape.circle)
        .map((decoration) => decoration.color)
        .toList();
    expect(dotColors, [const Color(0xFF1565C0), const Color(0xFFD84315)]);
  });

  testWidgets('丸マーク設定でも1人の予定は従来どおり単色で塗る（Issue #112）', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(
      _wrap(firestore, multiMemberDisplay: MultiMemberEventDisplay.dots),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<EventBar>(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == '会議',
      ),
    );

    // 参加者が 1 人なら丸マークは付けず単色のまま（memberDots を渡さない）。
    expect(bar.memberDots, isFalse);
    expect(bar.colors, [const Color(0xFF1565C0)]);
  });

  testWidgets('月表示は前後月セルにある予定も表示する（Issue #59）', (tester) async {
    final firestore = await _seedAdjacentMonthEvents();

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 1, 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年1月'), findsOneWidget);
    expect(find.text('前月末の予定'), findsOneWidget);
    expect(find.text('翌月初の予定'), findsOneWidget);
  });

  testWidgets('同名で期間が重なる予定は1本に束ねて表示する（Issue #76）', (tester) async {
    // 7/5(日)〜7/7 と 7/6〜7/8 は同名・期間が重なるため 1 本（和集合）に束ねる。
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MergedEventBar), findsOneWidget);
    // 束ねた予定は普通の [EventBar] では描かない。
    expect(find.byType(EventBar), findsNothing);
    // タイトルは先頭に 1 回だけ表示する（人数バッジは廃止、Issue #76）。
    expect(find.text('旅行'), findsOneWidget);
    expect(find.textContaining('👥'), findsNothing);

    // 予定が入っている日に、参加者色の〇（ドット）が描かれる。
    final dotColors = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(MergedEventBar),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.shape == BoxShape.circle)
        .map((decoration) => decoration.color)
        .toSet();
    // ぱぱ(青)・まま(橙)の色が両方ドットに現れる。
    expect(dotColors, contains(const Color(0xFF1565C0)));
    expect(dotColors, contains(const Color(0xFFD84315)));
  });

  testWidgets('自分が参加するマージ帯は地色を自分の色へ寄せる（Issue #105）', (tester) async {
    // 旅行(me)と旅行(mama)を束ねる。自分(me)が参加者に含まれるため、中立の
    // 地色ではなく自分の識別色を selfColor として受け取り、色で判別できる（FR-2）。
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<MergedEventBar>(find.byType(MergedEventBar));
    // 自分(ぱぱ)の識別色を受け取り、地色を自分の色へ寄せる。
    expect(bar.selfColor, const Color(0xFF1565C0));
  });

  testWidgets('自分が参加しないマージ帯は中立色のまま（Issue #105）', (tester) async {
    // まま単独の同名予定同士を束ねる。自分(me)は参加しないため selfColor は
    // null（従来どおり中立の地色）を保つ。
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<MergedEventBar>(find.byType(MergedEventBar));
    expect(bar.selfColor, isNull);
  });

  testWidgets('期間が離れた同名予定は束ねない（Issue #76）', (tester) async {
    // 7/5〜7/6 と 7/9〜7/10 は間に空き日（7/7・7/8）があるため別グループのまま。
    final firestore = await _seedTitledEvents([
      (
        title: '帰省',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 6, 18),
        type: EventType.confirmed,
      ),
      (
        title: '帰省',
        creator: 'mama',
        start: DateTime(2026, 7, 9, 9),
        end: DateTime(2026, 7, 10, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MergedEventBar), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == '帰省',
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('マージOFFなら同名予定を束ねず従来表示に戻す（Issue #76）', (tester) async {
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(
        firestore,
        initialFocusedDay: DateTime(2026, 7, 1),
        mergeEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MergedEventBar), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is EventBar && widget.title == '旅行',
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('仮/確定が混在するグループは仮スタイルで束ねる（Issue #76）', (tester) async {
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.tentative,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<MergedEventBar>(find.byType(MergedEventBar));
    // 1 件でも仮があれば仮スタイル（安全側、FR-3）。
    expect(bar.type, EventType.tentative);
  });

  testWidgets('束ねたバーは長押しで内訳シートを開き、行から編集へ遷移する（Issue #76 / #105）', (
    tester,
  ) async {
    final firestore = await _seedTitledEvents([
      (
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5, 9),
        end: DateTime(2026, 7, 7, 18),
        type: EventType.confirmed,
      ),
      (
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6, 9),
        end: DateTime(2026, 7, 8, 18),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    // Issue #105: 単タップではシートを開かない（ミスタップ対策。日選択へ透過する）。
    // テスト環境（kIsWeb=false）では長押しでシートを開く。
    await tester.tap(find.byType(MergedEventBar));
    await tester.pumpAndSettle();
    expect(find.byType(EventTypeBadge), findsNothing);

    await tester.longPress(find.byType(MergedEventBar));
    await tester.pumpAndSettle();

    // 内訳シートに各予定（2 件）の種別バッジが並ぶ。
    expect(find.byType(EventTypeBadge), findsNWidgets(2));

    // 行タップで予定編集画面へ遷移する。
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('EVENT_EDIT_SCREEN'), findsOneWidget);
  });

  testWidgets('月をまたぐマージ帯は翌月ビューでも同じマージ表示を保つ（Issue #108）', (tester) async {
    // 夏休み: ぱぱは 8/24 まで・ままは 8/31 まで。9 月ビューのグリッド
    // （8/30〜）にはぱぱの予定が重ならないが、取得をグリッドぴったりに絞ると
    // グループ構成が月によって変わり、8 月ビューではマージ帯だった 8/30〜31 が
    // 9 月ビューでは まま単独の予定バーに化けて表示がずれる。
    final firestore = await _seedTitledEvents([
      (
        title: '夏休み',
        creator: 'me',
        start: DateTime(2026, 7, 18),
        end: DateTime(2026, 8, 24),
        type: EventType.confirmed,
      ),
      (
        title: '夏休み',
        creator: 'mama',
        start: DateTime(2026, 7, 18),
        end: DateTime(2026, 8, 31),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 9, 1)),
    );
    await tester.pumpAndSettle();

    // 8 月ビューと同じく、8/30〜31 はマージ帯として描く（単独バーに化けない）。
    expect(find.byType(MergedEventBar), findsOneWidget);
    expect(find.byType(EventBar), findsNothing);

    final bar = tester.widget<MergedEventBar>(find.byType(MergedEventBar));
    // 実際の開始日（7/18）はグリッド外なので、開始端の角丸は付けない
    // （前月から続いて見せる）。終了端（8/31）は実際の終了日なので角丸を付ける。
    expect(bar.roundLeft, isFalse);
    expect(bar.roundRight, isTrue);
  });

  testWidgets('グリッド外へ続く帯の端には開始・終了の角丸を付けない（Issue #108）', (tester) async {
    // 7/18〜8/31 の予定を 7 月ビューで見る。グリッドは 8/8 で終わるが、予定は
    // その先へ続くため、最終週の右端に終了の角丸を付けない（そこで終わるように
    // 見せない）。開始端（7/18）はグリッド内の実際の開始日なので角丸を付ける。
    final firestore = await _seedTitledEvents([
      (
        title: '夏休み',
        creator: 'me',
        start: DateTime(2026, 7, 18),
        end: DateTime(2026, 8, 31),
        type: EventType.confirmed,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(firestore, initialFocusedDay: DateTime(2026, 7, 1)),
    );
    await tester.pumpAndSettle();

    final bars = tester
        .widgetList<EventBar>(
          find.byWidgetPredicate(
            (widget) => widget is EventBar && widget.title == '夏休み',
          ),
        )
        .toList();

    // 7 月ビュー（6/28〜8/8）では 7/18 の週から最終週まで 4 本に分かれる。
    expect(bars, hasLength(4));
    expect(bars.first.roundLeft, isTrue);
    expect(bars.first.roundRight, isFalse);
    expect(bars.last.roundLeft, isFalse);
    expect(bars.last.roundRight, isFalse);
  });

  testWidgets('カレンダーを切り替えると凡例が選択中カレンダーの参加者に切り替わる（Issue #130）', (tester) async {
    final firestore = await _firestoreWithTwoCalendars();
    // selectedCalendarIdProvider は上書きせず、calendarSelectionProvider を
    // 操作して切替を再現する。凡例が「全カレンダーの和集合」ではなく「選択中
    // カレンダーの参加者」に追従することを検証する（FR-2、基本設計 §6.3）。
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue('me'),
        resolvedEventMergeEnabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    await container.read(calendarSelectionProvider.notifier).select('cal-a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKanSukeTheme(),
          home: const CalendarScreen(),
          routes: {
            AppRoutes.dayEvents: (_) =>
                const Scaffold(body: Text('DAY_LIST_SCREEN')),
            AppRoutes.settings: (_) => const Scaffold(body: Text('SETTINGS')),
            AppRoutes.eventEdit: (_) =>
                const Scaffold(body: Text('EVENT_EDIT_SCREEN')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // カレンダー A（me+mama）を選択中は A の参加者だけが凡例に出る。
    expect(find.text('まま'), findsOneWidget);
    expect(find.text('きっず'), findsNothing);

    // カレンダー B（me+kids）へ切り替えると凡例も即座に追従する。
    await container.read(calendarSelectionProvider.notifier).select('cal-b');
    await tester.pumpAndSettle();

    expect(find.text('きっず'), findsOneWidget);
    expect(find.text('まま'), findsNothing);
  });
}

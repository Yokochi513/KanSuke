import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/events/presentation/day_events_screen.dart';
import 'package:kansuke/features/events/presentation/event_edit_args.dart';
import 'package:kansuke/models/models.dart';

/// テスト用のカレンダー ID（本番の ID は UUID。特別扱いされる固定 ID は無い）。
const testCalendarId = 'test-calendar';

/// Issue #170: 重ね表示の検証に使う 2 つめのカレンダー ID。
const _otherCalendarId = 'other-calendar';

/// 表示中カレンダー（Issue #170）。日別一覧は集合として受け取るため、
/// 表示している状態を固定で与える。
final _testCalendar = Calendar(
  id: testCalendarId,
  name: 'わが家',
  memberIds: const ['me', 'other'],
  creatorId: 'me',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

final _otherCalendar = Calendar(
  id: _otherCalendarId,
  name: 'しごと',
  memberIds: const ['me'],
  creatorId: 'me',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

final _day = DateTime(2026, 7, 5);

/// users は列挙禁止（Issue #89）。メンバーの色・名前は参加カレンダーの memberIds
/// から引くため、me と other が参加する既定カレンダーを用意する（FR-8）。
Future<FakeFirebaseFirestore> _firestoreWithCalendar() async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(testCalendarId).set({
    'name': 'わが家',
    'memberIds': ['me', 'other'],
    'creatorId': 'me',
    'ownerId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  return firestore;
}

Future<FakeFirebaseFirestore> _seed({
  bool withEvent = true,
  bool withParticipant = false,
  List<String>? participantIds,
  String memo = '',
}) async {
  final firestore = await _firestoreWithCalendar();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  if (withParticipant) {
    await firestore.collection('users').doc('other').set({
      'name': 'まま',
      'email': 'other@example.com',
      'color': '#C2185B',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }
  if (withEvent) {
    final start = DateTime(2026, 7, 5, 9);
    final eventParticipantIds =
        participantIds ??
        (withParticipant ? const ['me', 'other'] : const ['me']);
    final event = Event.create(
      title: '打ち合わせ',
      creatorId: 'me',
      participantIds: eventParticipantIds,
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: memo,
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
  }
  return firestore;
}

Future<FakeFirebaseFirestore> _seedCurrentUserPriority() async {
  final firestore = await _firestoreWithCalendar();
  for (final (id, name, color) in const [
    ('me', 'ぱぱ', '#1565C0'),
    ('other', 'まま', '#C2185B'),
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
    ('他人の朝予定', 'other', 8),
    ('自分の夜予定', 'me', 20),
  ]) {
    final start = DateTime(2026, 7, 5, hour);
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

Widget _wrap(
  FakeFirebaseFirestore firestore, {
  required List<Object?> editArgsSink,
  DateTime? selectedDay,
  List<Calendar>? visibleCalendars,
}) {
  final routeDay = selectedDay ?? _day;
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
      // 日別一覧の描画に集中するため、表示中カレンダーは固定する（カレンダーの
      // 解決自体は calendar_providers_test で検証する）。
      visibleCalendarsProvider.overrideWithValue(
        visibleCalendars ?? [_testCalendar],
      ),
    ],
    child: MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.dayEvents) {
          final effectiveDay = settings.arguments is DateTime
              ? DateUtils.dateOnly(settings.arguments! as DateTime)
              : routeDay;
          return MaterialPageRoute<void>(
            builder: (_) => const DayEventsScreen(),
            settings: RouteSettings(
              name: settings.name,
              arguments: effectiveDay,
            ),
          );
        }
        if (settings.name == AppRoutes.eventEdit) {
          editArgsSink.add(settings.arguments);
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('EDIT_SCREEN')),
          );
        }
        return null;
      },
      initialRoute: AppRoutes.dayEvents,
    ),
  );
}

/// Issue #170: 2 つのカレンダーにそれぞれ 1 件ずつ予定がある状態を用意する。
Future<FakeFirebaseFirestore> _seedTwoCalendars() async {
  final firestore = await _firestoreWithCalendar();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(_otherCalendarId).set({
    'name': 'しごと',
    'memberIds': ['me'],
    'creatorId': 'me',
    'ownerId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': now,
    'updatedAt': now,
  });
  for (final (title, calendarId, hour) in [
    ('わが家の予定', testCalendarId, 9),
    ('しごとの予定', _otherCalendarId, 13),
  ]) {
    final start = DateTime(2026, 7, 5, hour);
    final event = Event.create(
      title: title,
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const {},
      updatedBy: 'me',
      now: start,
      calendarId: calendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

/// Issue #146: 毎週の繰り返し予定（初回 2026/7/5 09:00）を 1 件だけ置く。
///
/// 展開すると 7/5・7/12・7/19… に現れるため、日別一覧から 1 回分だけ消しても
/// 他の回が残ることを検証できる。
Future<(FakeFirebaseFirestore, String)> _seedWeeklyRecurring() async {
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
    title: '習い事',
    creatorId: 'me',
    participantIds: const ['me'],
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const {},
    updatedBy: 'me',
    now: start,
    calendarId: testCalendarId,
    recurrenceFrequency: EventRecurrenceFrequency.weekly,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
  return (firestore, event.id);
}

/// Issue #146: 一覧の行から繰り返し予定の削除メニューを開く（「⋮」をタップ）。
Future<void> _openRecurringDeleteMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('繰り返し予定の削除'));
  await tester.pumpAndSettle();
}

/// 日別一覧のページを [days] 日ぶん送る（負なら過去へ）。
///
/// [WidgetTester.pumpWidget] を二度呼んでも既存のルートが再利用され対象日は
/// 変わらないため、画面のページ送り操作で別の日へ移動する。
Future<void> _moveDays(WidgetTester tester, int days) async {
  final tooltip = days >= 0 ? '翌日の予定へ' : '前日の予定へ';
  for (var i = 0; i < days.abs(); i++) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }
}

/// 一覧の各行に出るカレンダー名ラベル（Issue #170）。AppBar のカレンダー名と
/// 区別するため、[ListTile] の中に限定して探す。
Finder _calendarLabel(String name) =>
    find.descendant(of: find.byType(ListTile), matching: find.text(name));

/// ListTile の leading にある、メンバー色の丸ドット数を数える。
int _memberDotCount(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .where(
        (c) =>
            c.constraints ==
            const BoxConstraints.tightFor(width: 10, height: 10),
      )
      .length;
}

void main() {
  testWidgets('選択日の予定を参加者色・種別バッジ・時刻付きで一覧表示する', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('打ち合わせ'), findsOneWidget);
    expect(find.text('仮'), findsOneWidget); // 種別バッジ
    expect(find.textContaining('09:00〜10:00'), findsOneWidget);
    expect(find.textContaining('メモ:'), findsNothing);
  });

  testWidgets('メモ付き予定は一覧でメモ本文を確認できる', (tester) async {
    final firestore = await _seed(memo: '資料を印刷して持っていく');
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.textContaining('メモ: 資料を印刷して持っていく'), findsOneWidget);
  });

  testWidgets('参加者が1人の予定でも参加者名をタイトル横に表示する', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('参加: ぱぱ'), findsOneWidget);
    final titleCenterY = tester.getCenter(find.text('打ち合わせ')).dy;
    final participantsCenterY = tester.getCenter(find.text('参加: ぱぱ')).dy;

    expect((titleCenterY - participantsCenterY).abs(), lessThan(4));
  });

  testWidgets('退会済み参加者を含む予定も壊れず「退会したメンバー」で表示する（Issue #102）', (tester) async {
    // 参加者 'ghost' の users ドキュメントは無い（退会済み相当）。
    final firestore = await _seed(participantIds: const ['me', 'ghost']);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('打ち合わせ'), findsOneWidget);
    expect(find.text('参加: ぱぱ・退会したメンバー'), findsOneWidget);
    // 参加人数分（2 個）のドットが描かれる（退会済みはグレー）。
    expect(_memberDotCount(tester), 2);
  });

  testWidgets('参加者が複数いる予定は参加者名をタイトル横に表示する', (tester) async {
    final firestore = await _seed(withParticipant: true);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('参加: ぱぱ・まま'), findsOneWidget);
    final titleCenterY = tester.getCenter(find.text('打ち合わせ')).dy;
    final participantsCenterY = tester.getCenter(find.text('参加: ぱぱ・まま')).dy;

    expect((titleCenterY - participantsCenterY).abs(), lessThan(4));
  });

  testWidgets('参加者がいる予定は先頭のドットが参加人数分になる', (tester) async {
    final withParticipant = await _seed(withParticipant: true);
    await tester.pumpWidget(_wrap(withParticipant, editArgsSink: []));
    await tester.pumpAndSettle();
    expect(_memberDotCount(tester), 2);
  });

  testWidgets('参加者が1人の予定は先頭のドットが1個になる', (tester) async {
    final soloEvent = await _seed();
    await tester.pumpWidget(_wrap(soloEvent, editArgsSink: []));
    await tester.pumpAndSettle();
    expect(_memberDotCount(tester), 1);
  });

  testWidgets('日別一覧では自分が参加者の予定を先頭に表示する', (tester) async {
    final firestore = await _seedCurrentUserPriority();
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    final myEventTop = tester.getTopLeft(find.text('自分の夜予定')).dy;
    final otherEventTop = tester.getTopLeft(find.text('他人の朝予定')).dy;

    expect(myEventTop, lessThan(otherEventTop));
  });

  testWidgets('選択日に重なる期間予定を一覧表示する', (tester) async {
    final firestore = await _seed(withEvent: false);
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

    await tester.pumpWidget(
      _wrap(firestore, editArgsSink: [], selectedDay: DateTime(2026, 7, 6)),
    );
    await tester.pumpAndSettle();

    expect(find.text('テスト週間'), findsOneWidget);
    expect(find.textContaining('7/5 09:00〜7/7 10:00'), findsOneWidget);
  });

  testWidgets('予定なしの日は空状態を表示する', (tester) async {
    final firestore = await _seed(withEvent: false);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('予定はありません'), findsOneWidget);
  });

  testWidgets('前日・翌日ボタンで日別一覧の日付を切り替えられる', (tester) async {
    final firestore = await _seed(withEvent: false);
    final nextDay = DateTime(2026, 7, 6, 9);
    final nextDayEvent = Event.create(
      title: '翌日の予定',
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: nextDay,
      endAt: nextDay.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const {},
      updatedBy: 'me',
      now: nextDay,
      calendarId: testCalendarId,
    );
    await firestore
        .collection('events')
        .doc(nextDayEvent.id)
        .set(nextDayEvent.toFirestore(useServerTimestamp: false));

    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('2026/07/05 の予定'), findsOneWidget);
    expect(find.text('翌日の予定'), findsNothing);

    await tester.tap(find.byTooltip('翌日の予定へ'));
    await tester.pumpAndSettle();

    expect(find.text('2026/07/06 の予定'), findsOneWidget);
    expect(find.text('翌日の予定'), findsOneWidget);

    await tester.tap(find.byTooltip('前日の予定へ'));
    await tester.pumpAndSettle();

    expect(find.text('2026/07/05 の予定'), findsOneWidget);
    expect(find.text('翌日の予定'), findsNothing);
  });

  testWidgets('項目タップで編集画面へ既存予定を渡して遷移する', (tester) async {
    final firestore = await _seed();
    final sink = <Object?>[];
    await tester.pumpWidget(_wrap(firestore, editArgsSink: sink));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打ち合わせ'));
    await tester.pumpAndSettle();

    expect(find.text('EDIT_SCREEN'), findsOneWidget);
    expect(sink.single, isA<EventEditArgs>());
    expect((sink.single as EventEditArgs).isCreate, isFalse);
  });

  testWidgets('参加者フィルタで選んだメンバーの予定だけに絞り込める（Issue #78）', (tester) async {
    // 同じ日に「ぱぱだけ」「ままだけ」の予定を1件ずつ置く。
    final firestore = await _seed(withEvent: false, withParticipant: true);
    for (final (title, participantId, hour) in const [
      ('ぱぱの予定', 'me', 9),
      ('ままの予定', 'other', 10),
    ]) {
      final start = DateTime(2026, 7, 5, hour);
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

    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    // 絞り込み前は両方見える。
    expect(find.text('ぱぱの予定'), findsOneWidget);
    expect(find.text('ままの予定'), findsOneWidget);

    // フィルタシートを開き「まま」を選ぶ。
    await tester.tap(find.byTooltip('参加者で絞り込み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('まま'));
    await tester.pumpAndSettle();
    // シートを閉じて一覧へ戻る。
    Navigator.of(tester.element(find.text('参加者で絞り込み'))).pop();
    await tester.pumpAndSettle();

    // ままの予定だけが残る。
    expect(find.text('ままの予定'), findsOneWidget);
    expect(find.text('ぱぱの予定'), findsNothing);

    // 「すべて表示」で全件に戻す。
    await tester.tap(find.byTooltip('参加者で絞り込み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('すべて表示'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('参加者で絞り込み'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('ぱぱの予定'), findsOneWidget);
    expect(find.text('ままの予定'), findsOneWidget);
  });

  group('複数カレンダーの重ね表示（Issue #170）', () {
    testWidgets('表示中カレンダーすべての予定を1つの一覧に重ねて表示する', (tester) async {
      final firestore = await _seedTwoCalendars();
      await tester.pumpWidget(
        _wrap(
          firestore,
          editArgsSink: [],
          visibleCalendars: [_testCalendar, _otherCalendar],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('わが家の予定'), findsOneWidget);
      expect(find.text('しごとの予定'), findsOneWidget);
    });

    testWidgets('どのカレンダーの予定かを名前ラベルで判別できる', (tester) async {
      final firestore = await _seedTwoCalendars();
      await tester.pumpWidget(
        _wrap(
          firestore,
          editArgsSink: [],
          visibleCalendars: [_testCalendar, _otherCalendar],
        ),
      );
      await tester.pumpAndSettle();

      // 色は「誰の予定か」のままなので、カレンダーの違いは名前ラベルで示す。
      expect(_calendarLabel('わが家'), findsOneWidget);
      expect(_calendarLabel('しごと'), findsOneWidget);
    });

    testWidgets('1つだけ表示しているときはカレンダー名を出さない（自明なため）', (tester) async {
      final firestore = await _seedTwoCalendars();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      expect(find.text('わが家の予定'), findsOneWidget);
      expect(find.text('しごとの予定'), findsNothing);
      // AppBar のカレンダー名とは別に、一覧側にはラベルを出さない。
      expect(_calendarLabel('わが家'), findsNothing);
    });
  });

  group('日画面から繰り返し予定のこの回だけ削除（Issue #146）', () {
    testWidgets('「この日だけ削除」でその回だけが消え、他の回は残る', (tester) async {
      final (firestore, eventId) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();
      expect(find.text('習い事'), findsOneWidget);

      await _openRecurringDeleteMenu(tester);
      await tester.tap(find.text('この日だけ削除'));
      await tester.pumpAndSettle();

      // 7/5 の回は一覧から消え、何が消えたのかを通知で伝える。
      expect(find.text('習い事'), findsNothing);
      expect(find.text('予定はありません'), findsOneWidget);
      expect(find.text('7月5日（日）の回だけ削除しました'), findsOneWidget);

      // 元ドキュメントは残り、7/5 の発生日だけが例外日に入る。
      final doc = await firestore.collection('events').doc(eventId).get();
      final data = doc.data()!;
      expect(data['deleted'], isFalse);
      expect(data['recurrenceUntil'], isNull);
      expect(
        (data['recurrenceExceptions'] as List<Object?>)
            .map((value) => (value! as Timestamp).toDate())
            .toList(),
        [DateTime(2026, 7, 5, 9)],
      );

      // 翌週（7/12）の回はそのまま残っている。
      await _moveDays(tester, 7);
      expect(find.text('2026/07/12 の予定'), findsOneWidget);
      expect(find.text('習い事'), findsOneWidget);
    });

    testWidgets('メニューは削除範囲と残る回を文言で示す', (tester) async {
      final (firestore, _) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await _openRecurringDeleteMenu(tester);

      // どの回を操作しているかを見出しで示す。
      expect(find.text('繰り返し予定の削除'), findsOneWidget);
      expect(find.text('「習い事」2026年7月5日（日）の回'), findsOneWidget);
      // 各選択肢が「どこまで消えるか」を言い切る。
      expect(find.text('この日だけ削除'), findsOneWidget);
      expect(find.text('7月5日（日）の回だけ消えます。他の回は残ります'), findsOneWidget);
      expect(find.text('この日以降をすべて削除'), findsOneWidget);
      expect(find.text('すべての回を削除'), findsOneWidget);
      expect(find.text('過去の回も含めて繰り返し予定が丸ごと消えます'), findsOneWidget);
    });

    testWidgets('先頭の回では「この日以降」が全体削除になることを文言で伝える', (tester) async {
      final (firestore, _) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await _openRecurringDeleteMenu(tester);

      // 7/5 は初回なので「これ以降」を選ぶと 1 件も残らない。
      expect(find.text('7月5日（日）が最初の回のため、繰り返し予定が丸ごと消えます'), findsOneWidget);
    });

    testWidgets('2回目以降で「この日以降をすべて削除」を選ぶと前の回だけ残る', (tester) async {
      final (firestore, eventId) = await _seedWeeklyRecurring();
      await tester.pumpWidget(
        _wrap(firestore, editArgsSink: [], selectedDay: DateTime(2026, 7, 12)),
      );
      await tester.pumpAndSettle();

      await _openRecurringDeleteMenu(tester);
      expect(find.text('7月12日（日）より前の回は残ります'), findsOneWidget);
      await tester.tap(find.text('この日以降をすべて削除'));
      await tester.pumpAndSettle();

      expect(find.text('7月12日（日）以降の回を削除しました'), findsOneWidget);
      final data = (await firestore.collection('events').doc(eventId).get())
          .data()!;
      expect(data['deleted'], isFalse);
      expect(
        (data['recurrenceUntil']! as Timestamp).toDate(),
        DateTime(2026, 7, 12, 9),
      );

      // 打ち切り前の 7/5 の回は残る。
      await _moveDays(tester, -7);
      expect(find.text('2026/07/05 の予定'), findsOneWidget);
      expect(find.text('習い事'), findsOneWidget);
    });

    testWidgets('「すべての回を削除」は繰り返し予定を丸ごと削除する', (tester) async {
      final (firestore, eventId) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await _openRecurringDeleteMenu(tester);
      await tester.tap(find.text('すべての回を削除'));
      await tester.pumpAndSettle();

      expect(find.text('繰り返し予定をすべて削除しました'), findsOneWidget);
      final data = (await firestore.collection('events').doc(eventId).get())
          .data()!;
      expect(data['deleted'], isTrue);

      // 他の回も残らない。
      await _moveDays(tester, 7);
      expect(find.text('2026/07/12 の予定'), findsOneWidget);
      expect(find.text('習い事'), findsNothing);
    });

    testWidgets('キャンセルすると何も削除されない', (tester) async {
      final (firestore, eventId) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await _openRecurringDeleteMenu(tester);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('習い事'), findsOneWidget);
      final data = (await firestore.collection('events').doc(eventId).get())
          .data()!;
      expect(data['deleted'], isFalse);
      expect(data['recurrenceExceptions'], isEmpty);
    });

    testWidgets('左スワイプでも同じ削除メニューを開ける', (tester) async {
      final (firestore, eventId) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await tester.drag(find.text('習い事'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('この日だけ削除'), findsOneWidget);
      await tester.tap(find.text('この日だけ削除'));
      await tester.pumpAndSettle();

      expect(find.text('予定はありません'), findsOneWidget);
      final data = (await firestore.collection('events').doc(eventId).get())
          .data()!;
      expect((data['recurrenceExceptions'] as List<Object?>), hasLength(1));
    });

    testWidgets('長押しでも削除メニューを開ける', (tester) async {
      final (firestore, _) = await _seedWeeklyRecurring();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('習い事'));
      await tester.pumpAndSettle();

      expect(find.text('繰り返し予定の削除'), findsOneWidget);
    });

    testWidgets('繰り返しでない予定には削除導線を出さない', (tester) async {
      final firestore = await _seed();
      await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
      await tester.pumpAndSettle();

      expect(find.byTooltip('繰り返し予定の削除'), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('メニューを開いてもタップでの編集画面遷移は妨げない', (tester) async {
      final (firestore, _) = await _seedWeeklyRecurring();
      final sink = <Object?>[];
      await tester.pumpWidget(_wrap(firestore, editArgsSink: sink));
      await tester.pumpAndSettle();

      await tester.tap(find.text('習い事'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_SCREEN'), findsOneWidget);
      expect((sink.single as EventEditArgs).isCreate, isFalse);
    });
  });

  testWidgets('新規作成ボタンで対象日を初期値に編集画面を開く', (tester) async {
    final firestore = await _seed(withEvent: false);
    final sink = <Object?>[];
    await tester.pumpWidget(_wrap(firestore, editArgsSink: sink));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    expect(find.text('EDIT_SCREEN'), findsOneWidget);
    final args = sink.single as EventEditArgs;
    expect(args.isCreate, isTrue);
    expect(args.initialDate, _day);
  });
}

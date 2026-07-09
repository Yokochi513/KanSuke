import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/events/presentation/day_events_screen.dart';
import 'package:kansuke/features/events/presentation/event_edit_args.dart';
import 'package:kansuke/models/models.dart';

final _day = DateTime(2026, 7, 5);

Future<FakeFirebaseFirestore> _seed({
  bool withEvent = true,
  bool withParticipant = false,
  List<String>? participantIds,
  String memo = '',
}) async {
  final firestore = FakeFirebaseFirestore();
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
      reminderOffsets: const [60],
      updatedBy: 'me',
      now: start,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));
  }
  return firestore;
}

Future<FakeFirebaseFirestore> _seedCurrentUserPriority() async {
  final firestore = FakeFirebaseFirestore();
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

Widget _wrap(
  FakeFirebaseFirestore firestore, {
  required List<Object?> editArgsSink,
  DateTime? selectedDay,
}) {
  final routeDay = selectedDay ?? _day;
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
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

  testWidgets('参加者が1人の予定でも参加者名を副次表示する', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('参加: ぱぱ'), findsOneWidget);
  });

  testWidgets('参加者が複数いる予定は参加者名を副次表示する', (tester) async {
    final firestore = await _seed(withParticipant: true);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.textContaining('参加: ぱぱ・まま'), findsOneWidget);
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
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
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
      reminderOffsets: const [],
      updatedBy: 'me',
      now: nextDay,
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

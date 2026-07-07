import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/events/presentation/day_events_screen.dart';
import 'package:kansuke/features/events/presentation/event_edit_args.dart';
import 'package:kansuke/models/models.dart';

final _day = DateTime(2026, 7, 5);

Future<FakeFirebaseFirestore> _seed({
  bool withEvent = true,
  bool withParticipant = false,
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
    final event = Event.create(
      title: '打ち合わせ',
      ownerId: 'me',
      participantIds: withParticipant ? const ['me', 'other'] : const [],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
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

Widget _wrap(
  FakeFirebaseFirestore firestore, {
  required List<Object?> editArgsSink,
}) {
  return ProviderScope(
    overrides: [firestoreProvider.overrideWithValue(firestore)],
    child: MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.dayEvents) {
          return MaterialPageRoute<void>(
            builder: (_) => const DayEventsScreen(),
            settings: RouteSettings(name: settings.name, arguments: _day),
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
  testWidgets('選択日の予定を所有者色・種別バッジ・時刻付きで一覧表示する', (tester) async {
    final firestore = await _seed();
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('打ち合わせ'), findsOneWidget);
    expect(find.text('仮'), findsOneWidget); // 種別バッジ
    expect(find.textContaining('09:00〜10:00'), findsOneWidget);
    expect(find.textContaining('ぱぱ'), findsOneWidget); // 所有者名
  });

  testWidgets('参加者がいる予定は参加者名を副次表示する', (tester) async {
    final firestore = await _seed(withParticipant: true);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.textContaining('参加: まま'), findsOneWidget);
  });

  testWidgets('参加者がいる予定は先頭のドットが参加人数分になる', (tester) async {
    final withParticipant = await _seed(withParticipant: true);
    await tester.pumpWidget(_wrap(withParticipant, editArgsSink: []));
    await tester.pumpAndSettle();
    expect(_memberDotCount(tester), 2);
  });

  testWidgets('参加者がいない予定は先頭のドットが所有者の1個になる', (tester) async {
    final ownerOnly = await _seed();
    await tester.pumpWidget(_wrap(ownerOnly, editArgsSink: []));
    await tester.pumpAndSettle();
    expect(_memberDotCount(tester), 1);
  });

  testWidgets('予定なしの日は空状態を表示する', (tester) async {
    final firestore = await _seed(withEvent: false);
    await tester.pumpWidget(_wrap(firestore, editArgsSink: []));
    await tester.pumpAndSettle();

    expect(find.text('予定はありません'), findsOneWidget);
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

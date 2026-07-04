import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
    ownerId: 'me',
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

Widget _wrap(FakeFirebaseFirestore firestore) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue('me'),
    ],
    child: MaterialApp(
      home: const CalendarScreen(),
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

  testWidgets('日付タップで日別一覧へ遷移する', (tester) async {
    final today = DateTime.now();
    final firestore = await _seed(today: today);

    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('DAY_LIST_SCREEN'), findsOneWidget);
  });

  testWidgets('EventDot は確定=塗り・仮=枠付きで種別を区別する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              EventDot(color: Color(0xFF1565C0), type: EventType.confirmed),
              EventDot(color: Color(0xFF1565C0), type: EventType.tentative),
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
}

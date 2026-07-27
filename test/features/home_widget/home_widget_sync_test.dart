import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/home_widget/application/home_widget_payload.dart';
import 'package:kansuke/features/home_widget/data/home_widget_client.dart';
import 'package:kansuke/features/home_widget/presentation/home_widget_sync.dart';
import 'package:kansuke/models/models.dart';

const _calendarId = 'test-calendar';

final _calendar = Calendar(
  id: _calendarId,
  name: 'わが家',
  memberIds: const ['me'],
  creatorId: 'me',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// 書き出されたペイロードを記録するだけのクライアント。
class _RecordingHomeWidgetClient implements HomeWidgetClient {
  final pushed = <String>[];

  @override
  Future<void> push(String payload) async => pushed.add(payload);
}

Future<FakeFirebaseFirestore> _seed({required DateTime start}) async {
  final firestore = FakeFirebaseFirestore();
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(_calendarId).set({
    'name': 'わが家',
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
  final event = Event.create(
    title: '打ち合わせ',
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
    calendarId: _calendarId,
  );
  await firestore
      .collection('events')
      .doc(event.id)
      .set(event.toFirestore(useServerTimestamp: false));
  return firestore;
}

Widget _wrap(
  FakeFirebaseFirestore firestore,
  _RecordingHomeWidgetClient client, {
  required String? uid,
}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(uid),
      visibleCalendarsProvider.overrideWithValue([_calendar]),
      homeWidgetClientProvider.overrideWithValue(client),
    ],
    child: const MaterialApp(
      home: HomeWidgetSync(child: Scaffold(body: Text('APP'))),
    ),
  );
}

Map<String, Object?> _decode(String payload) =>
    jsonDecode(payload) as Map<String, Object?>;

List<Object?> _entriesOn(Map<String, Object?> payload, DateTime day) {
  final days = (payload['days']! as List).cast<Map<String, Object?>>();
  final date = formatHomeWidgetDate(day);
  return days.firstWhere((entry) => entry['date'] == date)['entries']! as List;
}

void main() {
  // 「今日」はウィジェット側と同じく端末の現在日で決まるため、テストも実時刻を基準にする。
  final today = DateUtils.dateOnly(DateTime.now());

  testWidgets('表示中カレンダーの予定をウィジェットへ書き出す（Issue #127）', (tester) async {
    final firestore = await _seed(start: today.add(const Duration(hours: 9)));
    final client = _RecordingHomeWidgetClient();

    await tester.pumpWidget(_wrap(firestore, client, uid: 'me'));
    await tester.pumpAndSettle();

    expect(client.pushed, isNotEmpty);
    final payload = _decode(client.pushed.last);
    expect(payload['signedIn'], isTrue);
    expect(payload['version'], homeWidgetPayloadVersion);

    final entries = _entriesOn(payload, today).cast<Map<String, Object?>>();
    expect(entries.single['title'], '打ち合わせ');
    expect(entries.single['time'], '09:00');
    // FR-2: 参加者の識別色が載る。
    expect(entries.single['colors'], ['#1565C0']);
  });

  testWidgets('同じ内容で再描画しても書き込みを繰り返さない', (tester) async {
    final firestore = await _seed(start: today.add(const Duration(hours: 9)));
    final client = _RecordingHomeWidgetClient();

    await tester.pumpWidget(_wrap(firestore, client, uid: 'me'));
    await tester.pumpAndSettle();
    final countAfterFirstBuild = client.pushed.length;

    await tester.pump();
    await tester.pumpAndSettle();

    expect(client.pushed.length, countAfterFirstBuild);
  });

  testWidgets('サインアウト中は予定を書き出さない（NFR-4）', (tester) async {
    final firestore = await _seed(start: today.add(const Duration(hours: 9)));
    final client = _RecordingHomeWidgetClient();

    await tester.pumpWidget(_wrap(firestore, client, uid: null));
    await tester.pumpAndSettle();

    final payload = _decode(client.pushed.last);
    expect(payload['signedIn'], isFalse);
    expect(payload['days'], isEmpty);
  });
}

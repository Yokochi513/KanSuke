import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/models/models.dart';

void main() {
  Event buildEvent() {
    return Event(
      id: 'event-1',
      title: '通院',
      creatorId: 'user-1',
      participantIds: const ['user-1', 'user-2'],
      startAt: DateTime.utc(2026, 7, 10, 1),
      endAt: DateTime.utc(2026, 7, 10, 2),
      allDay: false,
      type: EventType.tentative,
      memo: '診察券を持参',
      reminderOffsets: const [60, 1440],
      updatedBy: 'user-1',
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 2),
      deleted: false,
    );
  }

  test('Firestore Mapとの往復で値を維持する', () {
    final event = buildEvent();

    final map = event.toFirestore(useServerTimestamp: false);
    final restored = Event.fromMap(event.id, map);

    expect(restored.id, event.id);
    expect(restored.title, event.title);
    expect(restored.creatorId, event.creatorId);
    expect(restored.participantIds, event.participantIds);
    expect(restored.startAt, event.startAt);
    expect(restored.endAt, event.endAt);
    expect(restored.allDay, event.allDay);
    expect(restored.type, event.type);
    expect(restored.memo, event.memo);
    expect(restored.reminderOffsets, event.reminderOffsets);
    expect(restored.updatedBy, event.updatedBy);
    expect(restored.createdAt, event.createdAt);
    expect(restored.updatedAt, event.updatedAt);
    expect(restored.deleted, event.deleted);
    expect(map['id'], event.id);
  });

  test('copyWithでtypeだけを仮から確定へ変更できる', () {
    final tentative = buildEvent();

    final confirmed = tentative.copyWith(type: EventType.confirmed);

    expect(confirmed.type, EventType.confirmed);
    expect(confirmed.id, tentative.id);
    expect(confirmed.title, tentative.title);
  });

  test('通常の書き込みではupdatedAtにserverTimestampを設定する', () {
    expect(buildEvent().toFirestore()['updatedAt'], isA<FieldValue>());
  });

  test('updatedAtがpending write中のnullでも例外にせず暫定値を返す', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map['updatedAt'] = null;

    final restored = Event.fromMap('event-1', map);

    expect(restored.updatedAt, isNotNull);
  });

  test('participantIdsが未保存の既存ドキュメントは空リストにフォールバックする', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map.remove('participantIds');

    final restored = Event.fromMap('event-1', map);

    expect(restored.participantIds, isEmpty);
  });

  test('memberIdsは参加者を重複なく並べる', () {
    final event = buildEvent().copyWith(
      participantIds: ['user-2', 'user-1', 'user-3', 'user-2'],
    );

    expect(event.memberIds, ['user-2', 'user-1', 'user-3']);
  });

  test('参加者が空ならmemberIdsは作成者にフォールバックする', () {
    final event = buildEvent().copyWith(participantIds: []);

    expect(event.memberIds, ['user-1']);
  });

  test('生成ファクトリは重複しないUUIDを付与する', () {
    final now = DateTime.utc(2026, 7, 2);

    Event create() => Event.create(
      title: '予定',
      creatorId: 'user-1',
      startAt: now,
      endAt: now.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'user-1',
      now: now,
    );

    final first = create();
    final second = create();
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(first.id, matches(uuidPattern));
    expect(second.id, isNot(first.id));
    expect(first.deleted, isFalse);
  });
}

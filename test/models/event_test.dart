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
      reminderOffsets: const {
        'user-1': [60, 1440],
      },
      updatedBy: 'user-1',
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 2),
      deleted: false,
      calendarId: 'calendar-1',
      recurrenceFrequency: EventRecurrenceFrequency.weekly,
      recurrenceCount: 5,
      recurrenceExceptions: [DateTime.utc(2026, 7, 17, 1)],
      recurrenceUntil: DateTime.utc(2026, 8, 14, 1),
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
    expect(restored.calendarId, event.calendarId);
    expect(restored.recurrenceFrequency, event.recurrenceFrequency);
    expect(restored.recurrenceCount, event.recurrenceCount);
    expect(restored.recurrenceExceptions, event.recurrenceExceptions);
    expect(restored.recurrenceUntil, event.recurrenceUntil);
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

  // FR-5 / Issue #14: リマインドは各自が自分の分だけ設定する（uid → 分の map）。
  test('reminderOffsetsは設定した本人のuidごとに読み書きする', () {
    final event = buildEvent();

    final map = event.toFirestore(useServerTimestamp: false);
    final restored = Event.fromMap(event.id, map);

    expect(map['reminderOffsets'], {
      'user-1': [60, 1440],
    });
    expect(restored.reminderOffsetsFor('user-1'), [60, 1440]);
    expect(restored.reminderOffsetsFor('user-2'), isEmpty);
  });

  // 旧形式（予定で共有する number[]）は移行せず破棄する（Issue #14）。
  test('旧形式のreminderOffsets（配列）は設定なしとして読む', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map['reminderOffsets'] = const [60, 1440];

    final restored = Event.fromMap('event-1', map);

    expect(restored.reminderOffsets, isEmpty);
  });

  test('participantIdsが未保存の既存ドキュメントは空リストにフォールバックする', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map.remove('participantIds');

    final restored = Event.fromMap('event-1', map);

    expect(restored.participantIds, isEmpty);
  });

  // Issue #93: 旧・既定カレンダー（'default'）へのフォールバックは廃止した。
  // 移行スクリプトで全予定に calendarId が実在するため、欠損は不正なドキュメント。
  test('calendarIdを持たないドキュメントは読み込めない', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map.remove('calendarId');

    expect(() => Event.fromMap('event-1', map), throwsA(isA<TypeError>()));
  });

  test('recurrenceFrequencyが未保存の既存ドキュメントは単発予定として扱う', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map.remove('recurrenceFrequency');
    map.remove('recurrenceCount');

    final restored = Event.fromMap('event-1', map);

    expect(restored.recurrenceFrequency, isNull);
    expect(restored.recurrenceCount, isNull);
  });

  // #86: 例外日・打ち切り日の導入前ドキュメントは、それぞれ空・null にフォールバックする。
  test('recurrenceExceptions/Untilが未保存のドキュメントは空とnullにフォールバックする', () {
    final map = buildEvent().toFirestore(useServerTimestamp: false);
    map.remove('recurrenceExceptions');
    map.remove('recurrenceUntil');

    final restored = Event.fromMap('event-1', map);

    expect(restored.recurrenceExceptions, isEmpty);
    expect(restored.recurrenceUntil, isNull);
  });

  test('表示用の繰り返し発生日は編集時に元の日時へ戻せる', () {
    final event = buildEvent();
    final occurrence = event.occurrenceAt(
      startAt: DateTime.utc(2026, 7, 17, 1),
      endAt: DateTime.utc(2026, 7, 17, 2),
    );

    expect(occurrence.startAt, DateTime.utc(2026, 7, 17, 1));
    expect(occurrence.recurrenceMasterStartAt, event.startAt);
    expect(occurrence.masterEventForEditing.startAt, event.startAt);
    expect(occurrence.masterEventForEditing.endAt, event.endAt);
  });

  // #86: 展開した発生日・編集用の元ドキュメントは、例外日と打ち切り日を保持する。
  test('occurrenceAtとmasterEventForEditingは例外日と打ち切り日を引き継ぐ', () {
    final event = buildEvent();
    final occurrence = event.occurrenceAt(
      startAt: DateTime.utc(2026, 7, 17, 1),
      endAt: DateTime.utc(2026, 7, 17, 2),
    );

    expect(occurrence.recurrenceExceptions, event.recurrenceExceptions);
    expect(occurrence.recurrenceUntil, event.recurrenceUntil);
    expect(
      occurrence.masterEventForEditing.recurrenceExceptions,
      event.recurrenceExceptions,
    );
    expect(
      occurrence.masterEventForEditing.recurrenceUntil,
      event.recurrenceUntil,
    );
  });

  // #86: 予定編集での保存（copyWith）で例外日・打ち切り日が消えない。
  test('copyWithは例外日と打ち切り日を保持する', () {
    final event = buildEvent();

    final updated = event.copyWith(title: '変更後');

    expect(updated.recurrenceExceptions, event.recurrenceExceptions);
    expect(updated.recurrenceUntil, event.recurrenceUntil);
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
      reminderOffsets: const {},
      updatedBy: 'user-1',
      now: now,
      calendarId: 'calendar-1',
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

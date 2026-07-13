import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/models/models.dart';

void main() {
  Calendar buildCalendar() {
    return Calendar(
      id: 'calendar-1',
      name: 'わが家',
      memberIds: const ['user-1', 'user-2'],
      creatorId: 'user-1',
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 2),
    );
  }

  test('Firestore Mapとの往復で値を維持する', () {
    final calendar = buildCalendar();

    final map = calendar.toFirestore(useServerTimestamp: false);
    final restored = Calendar.fromMap(calendar.id, map);

    expect(restored.id, calendar.id);
    expect(restored.name, calendar.name);
    expect(restored.memberIds, calendar.memberIds);
    expect(restored.creatorId, calendar.creatorId);
    expect(restored.ownerId, calendar.ownerId);
    expect(restored.createdAt, calendar.createdAt);
    expect(restored.updatedAt, calendar.updatedAt);
  });

  test('ownerId が欠損していれば creatorId をオーナーとみなす（Issue #89）', () {
    // ownerId 導入前に作られたカレンダー（バックフィル未完了）。
    final restored = Calendar.fromMap('calendar-1', {
      'name': 'わが家',
      'memberIds': const ['user-1', 'user-2'],
      'creatorId': 'user-1',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 2)),
    });

    expect(restored.ownerId, 'user-1');
    expect(restored.isOwnedBy('user-1'), isTrue);
    expect(restored.isOwnedBy('user-2'), isFalse);
  });

  test('オーナーを移譲したカレンダーでは作成者ではなくオーナーが権限を持つ（Issue #89）', () {
    final transferred = buildCalendar().copyWith(ownerId: 'user-2');

    expect(transferred.creatorId, 'user-1');
    expect(transferred.isOwnedBy('user-1'), isFalse);
    expect(transferred.isOwnedBy('user-2'), isTrue);
    expect(transferred.toFirestore()['ownerId'], 'user-2');
  });

  test('copyWithでnameとmemberIdsだけを変更できる', () {
    final original = buildCalendar();

    final renamed = original.copyWith(
      name: '子供の習い事',
      memberIds: const ['user-1'],
    );

    expect(renamed.name, '子供の習い事');
    expect(renamed.memberIds, ['user-1']);
    expect(renamed.id, original.id);
    expect(renamed.creatorId, original.creatorId);
  });

  test('通常の書き込みではupdatedAtにserverTimestampを設定する', () {
    expect(buildCalendar().toFirestore()['updatedAt'], isA<FieldValue>());
  });

  test('生成ファクトリは重複しないUUIDを付与する', () {
    final now = DateTime.utc(2026, 7, 2);

    Calendar create() => Calendar.create(
      name: 'わが家',
      memberIds: const ['user-1'],
      creatorId: 'user-1',
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
  });
}

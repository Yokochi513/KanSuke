import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/models/models.dart';

void main() {
  test('Firestore Mapとの往復で値を維持する', () {
    final createdAt = DateTime.utc(2026, 7, 1, 10);
    final updatedAt = DateTime.utc(2026, 7, 2, 11);
    final user = User(
      id: 'user-1',
      name: '花子',
      email: 'hanako@example.com',
      color: '#FF3366',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final map = user.toFirestore(useServerTimestamp: false);
    final restored = User.fromMap(user.id, map);

    expect(restored.id, user.id);
    expect(restored.name, user.name);
    expect(restored.email, user.email);
    expect(restored.color, user.color);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
  });

  test('通常の書き込みではupdatedAtにserverTimestampを設定する', () {
    final now = DateTime.utc(2026, 7, 2);
    final user = User(
      id: 'user-1',
      name: '花子',
      email: 'hanako@example.com',
      color: '#FF3366',
      createdAt: now,
      updatedAt: now,
    );

    expect(user.toFirestore()['updatedAt'], isA<FieldValue>());
  });
}

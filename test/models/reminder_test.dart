import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/models/models.dart';

void main() {
  test('Firestore Mapとの往復で値を維持する', () {
    final reminder = Reminder(
      id: 'reminder-1',
      eventId: 'event-1',
      ownerId: 'user-1',
      triggerAt: DateTime.utc(2026, 7, 10),
      sent: false,
    );

    final restored = Reminder.fromMap(reminder.id, reminder.toFirestore());

    expect(restored.id, reminder.id);
    expect(restored.eventId, reminder.eventId);
    expect(restored.ownerId, reminder.ownerId);
    expect(restored.triggerAt, reminder.triggerAt);
    expect(restored.sent, reminder.sent);
  });

  test('生成ファクトリはUUIDを付与して未送信で作成する', () {
    final reminder = Reminder.create(
      eventId: 'event-1',
      ownerId: 'user-1',
      triggerAt: DateTime.utc(2026, 7, 10),
    );

    expect(
      reminder.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(reminder.sent, isFalse);
  });
}

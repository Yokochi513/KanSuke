import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'firestore_serialization.dart';

/// Event から派生し、Functions が配信管理する FR-5 のリマインド。
final class Reminder {
  const Reminder({
    required this.id,
    required this.eventId,
    required this.ownerId,
    required this.triggerAt,
    required this.sent,
  });

  factory Reminder.create({
    required String eventId,
    required String ownerId,
    required DateTime triggerAt,
    Uuid uuid = const Uuid(),
  }) {
    return Reminder(
      id: uuid.v4(),
      eventId: eventId,
      ownerId: ownerId,
      triggerAt: triggerAt,
      sent: false,
    );
  }

  factory Reminder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Reminder document ${snapshot.id} does not exist.');
    }
    return Reminder.fromMap(snapshot.id, data);
  }

  factory Reminder.fromMap(String id, FirestoreData data) {
    return Reminder(
      id: id,
      eventId: data['eventId'] as String,
      ownerId: data['ownerId'] as String,
      triggerAt: dateTimeFromFirestore(data['triggerAt'], 'triggerAt'),
      sent: data['sent'] as bool,
    );
  }

  final String id;
  final String eventId;
  final String ownerId;
  final DateTime triggerAt;
  final bool sent;

  FirestoreData toFirestore() {
    return {
      'eventId': eventId,
      'ownerId': ownerId,
      'triggerAt': Timestamp.fromDate(triggerAt),
      'sent': sent,
    };
  }

  Reminder copyWith({
    String? id,
    String? eventId,
    String? ownerId,
    DateTime? triggerAt,
    bool? sent,
  }) {
    return Reminder(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      ownerId: ownerId ?? this.ownerId,
      triggerAt: triggerAt ?? this.triggerAt,
      sent: sent ?? this.sent,
    );
  }
}

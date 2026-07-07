import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'firestore_serialization.dart';

enum EventType {
  tentative,
  confirmed;

  static EventType fromFirestore(String value) {
    return EventType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw FormatException('Unknown event type: $value'),
    );
  }
}

/// 予定データ。FR-1〜FR-3 / FR-5 の永続化単位。
final class Event {
  Event({
    required this.id,
    required this.title,
    required this.ownerId,
    required List<String> participantIds,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.type,
    required this.memo,
    required List<int> reminderOffsets,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
  }) : participantIds = UnmodifiableListView(participantIds),
       reminderOffsets = UnmodifiableListView(reminderOffsets);

  factory Event.create({
    required String title,
    required String ownerId,
    List<String> participantIds = const [],
    required DateTime startAt,
    required DateTime endAt,
    required bool allDay,
    required EventType type,
    required String memo,
    required List<int> reminderOffsets,
    required String updatedBy,
    required DateTime now,
    Uuid uuid = const Uuid(),
  }) {
    return Event(
      id: uuid.v4(),
      title: title,
      ownerId: ownerId,
      participantIds: participantIds,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      type: type,
      memo: memo,
      reminderOffsets: reminderOffsets,
      updatedBy: updatedBy,
      createdAt: now,
      updatedAt: now,
      deleted: false,
    );
  }

  factory Event.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Event document ${snapshot.id} does not exist.');
    }
    return Event.fromMap(snapshot.id, data);
  }

  factory Event.fromMap(String id, FirestoreData data) {
    return Event(
      id: id,
      title: data['title'] as String,
      ownerId: data['ownerId'] as String,
      // 参加者機能導入前のドキュメントにはキーが存在しないため空リストにフォールバックする。
      participantIds: (data['participantIds'] as List<Object?>? ?? const [])
          .map((id) => id as String)
          .toList(),
      startAt: dateTimeFromFirestore(data['startAt'], 'startAt'),
      endAt: dateTimeFromFirestore(data['endAt'], 'endAt'),
      allDay: data['allDay'] as bool,
      type: EventType.fromFirestore(data['type'] as String),
      memo: data['memo'] as String,
      reminderOffsets: (data['reminderOffsets'] as List<Object?>)
          .map((offset) => offset as int)
          .toList(),
      updatedBy: data['updatedBy'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      updatedAt: dateTimeFromFirestore(data['updatedAt'], 'updatedAt'),
      deleted: data['deleted'] as bool,
    );
  }

  final String id;
  final String title;
  final String ownerId;
  final List<String> participantIds;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final EventType type;
  final String memo;
  final List<int> reminderOffsets;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'id': id,
      'title': title,
      'ownerId': ownerId,
      'participantIds': participantIds.toList(),
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'allDay': allDay,
      'type': type.name,
      'memo': memo,
      'reminderOffsets': reminderOffsets.toList(),
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAtForFirestore(
        updatedAt,
        useServerTimestamp: useServerTimestamp,
      ),
      'deleted': deleted,
    };
  }

  Event copyWith({
    String? id,
    String? title,
    String? ownerId,
    List<String>? participantIds,
    DateTime? startAt,
    DateTime? endAt,
    bool? allDay,
    EventType? type,
    String? memo,
    List<int>? reminderOffsets,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      ownerId: ownerId ?? this.ownerId,
      participantIds: participantIds ?? this.participantIds,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      allDay: allDay ?? this.allDay,
      type: type ?? this.type,
      memo: memo ?? this.memo,
      reminderOffsets: reminderOffsets ?? this.reminderOffsets,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}

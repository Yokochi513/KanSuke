import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'calendar.dart';
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
    required this.creatorId,
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
    required this.calendarId,
  }) : participantIds = UnmodifiableListView(participantIds),
       reminderOffsets = UnmodifiableListView(reminderOffsets);

  factory Event.create({
    required String title,
    required String creatorId,
    List<String> participantIds = const [],
    required DateTime startAt,
    required DateTime endAt,
    required bool allDay,
    required EventType type,
    required String memo,
    required List<int> reminderOffsets,
    required String updatedBy,
    required DateTime now,
    required String calendarId,
    Uuid uuid = const Uuid(),
  }) {
    return Event(
      id: uuid.v4(),
      title: title,
      creatorId: creatorId,
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
      calendarId: calendarId,
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
      // 所有者(ownerId)から作成者(creatorId)へのフィールド改名前のドキュメントを
      // 読めるよう、旧キーへフォールバックする。
      creatorId: (data['creatorId'] ?? data['ownerId']) as String,
      // 参加者機能導入前のドキュメントにはキーが存在しないため空リストにフォールバックする。
      participantIds: (data['participantIds'] as List<Object?>? ?? const [])
          .map((id) => id as String)
          .toList(),
      startAt: dateTimeFromFirestore(data['startAt'], 'startAt'),
      endAt: dateTimeFromFirestore(data['endAt'], 'endAt'),
      allDay: data['allDay'] as bool,
      type: EventType.fromFirestore(data['type'] as String),
      memo: data['memo'] as String,
      // リマインド機能導入前や、何らかの理由でキーが欠落したドキュメントを
      // 読んでも例外にならないよう空リストにフォールバックする。
      reminderOffsets: (data['reminderOffsets'] as List<Object?>? ?? const [])
          .map((offset) => offset as int)
          .toList(),
      updatedBy: data['updatedBy'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      // updatedAt は serverTimestamp() 書き込みのため、サーバー確定前は
      // ローカルの現在時刻を暫定値として扱う（確定後のスナップショットで
      // 正しい値に更新される）。
      updatedAt: dateTimeFromFirestore(
        data['updatedAt'],
        'updatedAt',
        pendingWriteEstimate: DateTime.now().toUtc(),
      ),
      deleted: data['deleted'] as bool,
      // FR-8: 複数カレンダー機能導入前のドキュメントには calendarId が
      // 存在しないため、既定カレンダー（わが家）に属するものとして扱う。
      calendarId: (data['calendarId'] as String?) ?? defaultCalendarId,
    );
  }

  final String id;
  final String title;
  final String creatorId;
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
  final String calendarId;

  /// 色分け表示（月表示の分割バー・日別一覧の複数ドット）で使う表示順の ID 一覧。
  ///
  /// 参加者を重複なく並べたもの。参加者機能導入前の未移行ドキュメント等、
  /// 参加者が空の場合のみ作成者にフォールバックする（表示が空にならないように）。
  List<String> get memberIds {
    if (participantIds.isEmpty) return [creatorId];
    final seen = <String>{};
    return [
      for (final id in participantIds)
        if (seen.add(id)) id,
    ];
  }

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'id': id,
      'title': title,
      'creatorId': creatorId,
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
      'calendarId': calendarId,
    };
  }

  Event copyWith({
    String? id,
    String? title,
    String? creatorId,
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
    String? calendarId,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      creatorId: creatorId ?? this.creatorId,
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
      calendarId: calendarId ?? this.calendarId,
    );
  }
}

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

enum EventRecurrenceFrequency {
  weekly,
  monthly,
  yearly;

  static EventRecurrenceFrequency? fromFirestore(String? value) {
    if (value == null) return null;
    return EventRecurrenceFrequency.values.firstWhere(
      (frequency) => frequency.name == value,
      orElse: () =>
          throw FormatException('Unknown recurrence frequency: $value'),
    );
  }
}

const _unset = Object();

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
    this.recurrenceFrequency,
    this.recurrenceCount,
    this.recurrenceMasterStartAt,
    this.recurrenceMasterEndAt,
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
    EventRecurrenceFrequency? recurrenceFrequency,
    int? recurrenceCount,
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
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
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
      // FR-8: calendarId は必須（Issue #93）。旧・既定カレンダー（'default'）への
      // フォールバックは、移行スクリプトで全予定に calendarId が実在するように
      // なったため廃止した。
      calendarId: data['calendarId'] as String,
      recurrenceFrequency: EventRecurrenceFrequency.fromFirestore(
        data['recurrenceFrequency'] as String?,
      ),
      // Firestore の number は int 以外の num 実装で届く可能性があるため、
      // nil と型変換の境界をここで閉じる。
      recurrenceCount: (data['recurrenceCount'] as num?)?.toInt(),
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
  final EventRecurrenceFrequency? recurrenceFrequency;
  final int? recurrenceCount;

  /// 表示用に展開した繰り返し予定が、編集時に元の開始/終了へ戻るための値。
  ///
  /// Firestore には保存しない一時フィールド。null なら元ドキュメントそのもの。
  final DateTime? recurrenceMasterStartAt;
  final DateTime? recurrenceMasterEndAt;

  bool get isRecurring => recurrenceFrequency != null;

  bool get isRecurrenceOccurrence =>
      recurrenceMasterStartAt != null && recurrenceMasterEndAt != null;

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
    final startAtForFirestore = recurrenceMasterStartAt ?? startAt;
    final endAtForFirestore = recurrenceMasterEndAt ?? endAt;
    return {
      'id': id,
      'title': title,
      'creatorId': creatorId,
      'participantIds': participantIds.toList(),
      'startAt': Timestamp.fromDate(startAtForFirestore),
      'endAt': Timestamp.fromDate(endAtForFirestore),
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
      'recurrenceFrequency': recurrenceFrequency?.name,
      'recurrenceCount': recurrenceCount,
    };
  }

  Event occurrenceAt({required DateTime startAt, required DateTime endAt}) {
    return Event(
      id: id,
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
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: deleted,
      calendarId: calendarId,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
      recurrenceMasterStartAt: this.startAt,
      recurrenceMasterEndAt: this.endAt,
    );
  }

  Event get masterEventForEditing {
    if (!isRecurrenceOccurrence) return this;
    return Event(
      id: id,
      title: title,
      creatorId: creatorId,
      participantIds: participantIds,
      startAt: recurrenceMasterStartAt!,
      endAt: recurrenceMasterEndAt!,
      allDay: allDay,
      type: type,
      memo: memo,
      reminderOffsets: reminderOffsets,
      updatedBy: updatedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: deleted,
      calendarId: calendarId,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
    );
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
    Object? recurrenceFrequency = _unset,
    Object? recurrenceCount = _unset,
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
      recurrenceFrequency: identical(recurrenceFrequency, _unset)
          ? this.recurrenceFrequency
          : recurrenceFrequency as EventRecurrenceFrequency?,
      recurrenceCount: identical(recurrenceCount, _unset)
          ? this.recurrenceCount
          : recurrenceCount as int?,
      recurrenceMasterStartAt: recurrenceMasterStartAt,
      recurrenceMasterEndAt: recurrenceMasterEndAt,
    );
  }
}

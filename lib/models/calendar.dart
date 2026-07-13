import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'firestore_serialization.dart';

/// 旧・既定カレンダー（「わが家」）の固定ドキュメント ID。
///
/// 複数カレンダー機能の導入前に作られた `calendarId` 未設定の予定を「このカレンダーに
/// 属する」と解釈するための後方互換用（FR-8、`firestore.rules` の `eventCalendarId`
/// と対応）。新規カレンダーの自動生成には用いない（アカウント作成時に生成される
/// 個人カレンダーの ID は UUID）。
const String defaultCalendarId = 'default';

/// カレンダー（FR-8）。予定はこの単位にグルーピングされ、
/// `memberIds` に含まれるメンバーだけが閲覧・編集できる。
final class Calendar {
  Calendar({
    required this.id,
    required this.name,
    required List<String> memberIds,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
  }) : memberIds = UnmodifiableListView(memberIds);

  factory Calendar.create({
    required String name,
    required List<String> memberIds,
    required String creatorId,
    required DateTime now,
    Uuid uuid = const Uuid(),
  }) {
    return Calendar(
      id: uuid.v4(),
      name: name,
      memberIds: memberIds,
      creatorId: creatorId,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Calendar.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Calendar document ${snapshot.id} does not exist.');
    }
    return Calendar.fromMap(snapshot.id, data);
  }

  factory Calendar.fromMap(String id, FirestoreData data) {
    return Calendar(
      id: id,
      name: data['name'] as String,
      memberIds: (data['memberIds'] as List<Object?>? ?? const [])
          .map((id) => id as String)
          .toList(),
      creatorId: data['creatorId'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      updatedAt: dateTimeFromFirestore(
        data['updatedAt'],
        'updatedAt',
        pendingWriteEstimate: DateTime.now().toUtc(),
      ),
    );
  }

  final String id;
  final String name;
  final List<String> memberIds;
  final String creatorId;
  final DateTime createdAt;
  final DateTime updatedAt;

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'name': name,
      'memberIds': memberIds.toList(),
      'creatorId': creatorId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAtForFirestore(
        updatedAt,
        useServerTimestamp: useServerTimestamp,
      ),
    };
  }

  Calendar copyWith({
    String? id,
    String? name,
    List<String>? memberIds,
    String? creatorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Calendar(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      creatorId: creatorId ?? this.creatorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

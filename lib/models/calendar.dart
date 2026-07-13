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
///
/// オーナー（[ownerId]、Issue #89）はカレンダー名の変更・メンバーの削除・オーナー
/// 移譲ができる唯一のメンバー。[creatorId]（作成者）は監査用に不変で残す。
final class Calendar {
  /// [ownerId] を省略した場合は作成者をオーナーとみなす。ownerId 導入前に作られた
  /// カレンダー（バックフィル未完了）を読むための後方互換（Issue #89）。
  Calendar({
    required this.id,
    required this.name,
    required List<String> memberIds,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    String? ownerId,
  }) : memberIds = UnmodifiableListView(memberIds),
       ownerId = ownerId ?? creatorId;

  /// 新規カレンダーを作成する。作成者がそのままオーナーになる。
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
      ownerId: creatorId,
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
      ownerId: data['ownerId'] as String?,
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

  /// オーナー（Issue #89）。Firestore に欠損している場合は [creatorId]。
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// [uid] がこのカレンダーのオーナーか（名前の変更・メンバー削除・移譲の可否）。
  bool isOwnedBy(String? uid) => uid != null && uid == ownerId;

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'name': name,
      'memberIds': memberIds.toList(),
      'creatorId': creatorId,
      'ownerId': ownerId,
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
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Calendar(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      creatorId: creatorId ?? this.creatorId,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

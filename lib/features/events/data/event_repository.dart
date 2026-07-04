import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/models.dart';

/// events コレクションへの CRUD とリアルタイム取得を担う。
///
/// FR-1（予定の登録・閲覧）/ FR-6（同期）/ 基本設計 §3.2・§4。
/// - ドキュメント ID はクライアント生成 UUID（[Event.create]）。
/// - `updatedBy` は本人 uid、`updatedAt` は `serverTimestamp()` を付与する。
/// - 削除はソフト削除（`deleted=true`）として LWW で伝播させる（§4.2）。
class EventRepository {
  EventRepository({
    required FirebaseFirestore firestore,
    required String currentUid,
  }) : _firestore = firestore,
       _currentUid = currentUid;

  final FirebaseFirestore _firestore;
  final String _currentUid;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('events');

  /// 予定を作成する（ドキュメント ID は [event] の UUID）。
  ///
  /// `updatedBy` を本人に上書きし、`updatedAt` は serverTimestamp とする。
  Future<void> create(Event event) {
    final data = event.copyWith(updatedBy: _currentUid).toFirestore();
    return _events.doc(event.id).set(data);
  }

  /// 既存予定を全フィールド更新する。`updatedBy`/`updatedAt` を更新する。
  Future<void> update(Event event) {
    final data = event.copyWith(updatedBy: _currentUid).toFirestore();
    return _events.doc(event.id).set(data);
  }

  /// 仮↔確定の切替（FR-3）。`type` 更新のみで完結させる。
  Future<void> setType(String eventId, EventType type) {
    return _events.doc(eventId).update({
      'type': type.name,
      'updatedBy': _currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ソフト削除（§4.2）。物理削除はサーバ側の定期パージに委ねる。
  Future<void> softDelete(String eventId) {
    return _events.doc(eventId).update({
      'deleted': true,
      'updatedBy': _currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 期間 `[start, end)` の予定をリアルタイムに監視する（FR-4 の月表示に利用）。
  ///
  /// `deleted==false` かつ `startAt` 範囲で取得し `startAt` 昇順。
  /// 複合インデックス（deleted ASC, startAt ASC）を前提とする。
  /// Firestore の既定でローカルキャッシュ起点に描画される（NFR-1）。
  Stream<List<Event>> watchRange({
    required DateTime start,
    required DateTime end,
  }) {
    return _events
        .where('deleted', isEqualTo: false)
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Event.fromFirestore).toList());
  }
}

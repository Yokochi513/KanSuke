import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/models.dart';

/// events コレクションへの CRUD とリアルタイム取得を担う。
///
/// FR-1（予定の登録・閲覧）/ FR-6（同期）/ 基本設計 §3.2・§4。
/// - ドキュメント ID はクライアント生成 UUID（[Event.create]）。
/// - `updatedBy` は書き込み時に呼び出し側（本人 uid）から受け取る。
///   認証状態に依存しない購読グラフにして、サインアウト時のテアダウン中に
///   購読が dirty 化して再描画がビルド中に走るのを避ける。
/// - `updatedAt` は `serverTimestamp()` を付与する。
/// - 削除はソフト削除（`deleted=true`）として LWW で伝播させる（§4.2）。
class EventRepository {
  EventRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('events');

  /// 予定を作成する（ドキュメント ID は [event] の UUID）。
  ///
  /// `updatedBy` を [updatedBy] に上書きし、`updatedAt` は serverTimestamp とする。
  Future<void> create(Event event, {required String updatedBy}) {
    final data = event.copyWith(updatedBy: updatedBy).toFirestore();
    return _events.doc(event.id).set(data);
  }

  /// 既存予定を全フィールド更新する。`updatedBy`/`updatedAt` を更新する。
  Future<void> update(Event event, {required String updatedBy}) {
    final data = event.copyWith(updatedBy: updatedBy).toFirestore();
    return _events.doc(event.id).set(data);
  }

  /// 仮↔確定の切替（FR-3）。`type` 更新のみで完結させる。
  Future<void> setType(
    String eventId,
    EventType type, {
    required String updatedBy,
  }) {
    return _events.doc(eventId).update({
      'type': type.name,
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ソフト削除（§4.2）。物理削除はサーバ側の定期パージに委ねる。
  Future<void> softDelete(String eventId, {required String updatedBy}) {
    return _events.doc(eventId).update({
      'deleted': true,
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 期間 `[start, end)` の予定をリアルタイムに監視する（FR-4 の月表示に利用）。
  ///
  /// `deleted==false` かつ `[startAt, endAt]` が指定期間と重なる予定を取得し
  /// `startAt` 昇順で返す。
  /// 複合インデックス（deleted ASC, startAt ASC, endAt ASC）を前提とする。
  /// Firestore の既定でローカルキャッシュ起点に描画される（NFR-1）。
  Stream<List<Event>> watchRange({
    required DateTime start,
    required DateTime end,
  }) {
    // 既存の終日単日予定は startAt == endAt のため、終了境界は含める。
    return _events
        .where('deleted', isEqualTo: false)
        .where('startAt', isLessThan: Timestamp.fromDate(end))
        .where('endAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('startAt')
        .orderBy('endAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Event.fromFirestore).toList());
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';

const _logTag = 'CalendarRepository';

/// calendars コレクションへの CRUD とリアルタイム取得を担う（FR-8）。
///
/// - ドキュメント ID はクライアント生成 UUID（[Calendar.create]）。個人カレンダー
///   （アカウント作成時に自動生成）は Auth Blocking Function が同じ規約で作る。
/// - Security Rules 上、`memberIds` に自分が含まれる場合のみ read/write 可
///   （`firestore.rules` 参照）。
class CalendarRepository {
  CalendarRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _calendars =>
      _firestore.collection('calendars');

  /// 自分が参加しているカレンダーをリアルタイムに監視する（名前昇順）。
  Stream<List<Calendar>> watchMine(String uid) {
    return _calendars
        .where('memberIds', arrayContains: uid)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
          final calendars = <Calendar>[];
          for (final doc in snapshot.docs) {
            try {
              calendars.add(Calendar.fromFirestore(doc));
            } catch (error, stackTrace) {
              // 1件のドキュメント破損でカレンダー一覧全体が落ちないよう、
              // 当該ドキュメントだけ除外してログに残す。
              AppLogger.error(
                'Failed to parse calendar ${doc.id}, skipping it',
                tag: _logTag,
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
          return calendars;
        });
  }

  /// カレンダーを新規作成する（ドキュメント ID は [calendar] の UUID）。
  Future<void> create(Calendar calendar) {
    return _calendars.doc(calendar.id).set(calendar.toFirestore()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      AppLogger.error(
        'Failed to create calendar ${calendar.id}',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw error;
    });
  }

  /// 名前・参加者を更新する。
  ///
  /// `memberIds` は編集画面を開いた時点のスナップショットに対する差分
  /// （[addedMemberIds] / [removedMemberIds]）として受け取り、`runTransaction`
  /// でサーバー上の最新 `memberIds` にその差分だけを適用する。編集画面が
  /// 保持するメンバー一覧全体をそのまま上書きすると、画面を開いてから保存
  /// するまでの間に他デバイスが加えたメンバー変更（例: 誰かの参加）を
  /// サイレントに消してしまうため（read-modify-write の競合）。
  Future<void> updateNameAndMembers(
    String id, {
    required String name,
    required Set<String> addedMemberIds,
    required Set<String> removedMemberIds,
  }) {
    final ref = _calendars.doc(id);
    return _firestore
        .runTransaction((transaction) async {
          final snapshot = await transaction.get(ref);
          final current = ((snapshot.data()?['memberIds'] as List?) ?? const [])
              .map((id) => id as String)
              .toSet();
          final memberIds = {...current, ...addedMemberIds}
            ..removeAll(removedMemberIds);
          transaction.update(ref, {
            'name': name,
            'memberIds': memberIds.toList()..sort(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to update calendar $id',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }
}

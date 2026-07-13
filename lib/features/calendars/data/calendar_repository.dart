import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';
import 'calendar_membership_repository.dart';

const _logTag = 'CalendarRepository';

/// calendars コレクションへの CRUD とリアルタイム取得を担う（FR-8）。
///
/// - ドキュメント ID はクライアント生成 UUID（[Calendar.create]）。個人カレンダー
///   （アカウント作成時に自動生成）は Auth Blocking Function が同じ規約で作る。
/// - Security Rules 上、`memberIds` に自分が含まれる場合のみ read/write 可
///   （`firestore.rules` 参照）。
/// - `memberIds` / `ownerId` はクライアントから書き換えられない（Issue #89）。
///   メンバーの削除・退出・オーナー移譲は [CalendarMembershipRepository] を使う。
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

  /// カレンダー名を更新する（オーナーのみ、Issue #89）。
  ///
  /// `memberIds` / `ownerId` は Security Rules でクライアントから書き換えられない
  /// ため、ここでは名前だけを更新する。メンバーの削除・退出・オーナー移譲は
  /// [CalendarMembershipRepository]（Callable Function）経由で行う。
  Future<void> updateName(String id, String name) {
    return _calendars
        .doc(id)
        .update({'name': name, 'updatedAt': FieldValue.serverTimestamp()})
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

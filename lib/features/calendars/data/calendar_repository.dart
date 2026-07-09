import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';

const _logTag = 'CalendarRepository';

/// calendars コレクションへの CRUD とリアルタイム取得を担う（FR-8）。
///
/// - ドキュメント ID はクライアント生成 UUID（[Calendar.create]）。既定カレンダー
///   （わが家）のみ固定 ID [defaultCalendarId] を用いる（[ensureDefaultCalendar]）。
/// - Security Rules 上、`memberIds` に自分が含まれる場合のみ read/write 可
///   （既定カレンダーへの「参加」のみ特例で追加可、`firestore.rules` 参照）。
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
  Future<void> updateNameAndMembers(
    String id, {
    required String name,
    required List<String> memberIds,
  }) {
    return _calendars
        .doc(id)
        .update({
          'name': name,
          'memberIds': memberIds,
          'updatedAt': FieldValue.serverTimestamp(),
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

  /// 既定カレンダー（わが家）の存在を保証する（FR-8）。
  ///
  /// サインイン確定後に毎回冪等に呼び出す想定。`beforeUserCreated`
  /// （Auth Blocking Function）は新規アカウント作成時にしか発火せず、既に
  /// サインアップ済みの家族メンバーを事後的に既定カレンダーへ追加する手段に
  /// ならないため、クライアント側の初期化処理として実装する。
  ///
  /// `runTransaction` で読み取り→書き込みをアトミックに行い、複数端末が
  /// 同時に初回起動しても安全にする（read-then-act の競合を避ける）。
  /// - 未作成なら [knownMemberIds]（呼び出し時点で判明している家族全員）と
  ///   [uid] を含めて新規作成する。
  /// - 既に存在するが [uid] が未参加なら、既存メンバーを維持したまま
  ///   `arrayUnion` で追加する。
  Future<void> ensureDefaultCalendar({
    required String uid,
    required List<String> knownMemberIds,
  }) {
    final ref = _calendars.doc(defaultCalendarId);
    return _firestore
        .runTransaction((transaction) async {
          final snapshot = await transaction.get(ref);
          final now = FieldValue.serverTimestamp();
          if (!snapshot.exists) {
            final memberIds = {...knownMemberIds, uid}.toList();
            transaction.set(ref, {
              'name': 'わが家',
              'memberIds': memberIds,
              'creatorId': uid,
              'createdAt': now,
              'updatedAt': now,
            });
            return;
          }
          final existing =
              ((snapshot.data()?['memberIds'] as List?) ?? const [])
                  .map((id) => id as String)
                  .toSet();
          final toAdd = {...knownMemberIds, uid}.difference(existing);
          if (toAdd.isEmpty) return;
          transaction.update(ref, {
            'memberIds': FieldValue.arrayUnion(toAdd.toList()),
            'updatedAt': now,
          });
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to ensure default calendar',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }
}

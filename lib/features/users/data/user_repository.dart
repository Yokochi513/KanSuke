import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';

const _logTag = 'UserRepository';

/// users コレクションの参照を担う。
///
/// FR-2: 予定表示で使う家族メンバーの色・名前を提供する。
/// 基本設計 §2.2 のとおり users は家族全員が閲覧可・本人のみ更新可。
class UserRepository {
  UserRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// 家族メンバー一覧をリアルタイムに監視する（名前昇順）。
  Stream<List<User>> watchMembers() {
    return _users.orderBy('name').snapshots().map((snapshot) {
      final members = <User>[];
      for (final doc in snapshot.docs) {
        try {
          members.add(User.fromFirestore(doc));
        } catch (error, stackTrace) {
          // 1件のドキュメント破損でメンバー一覧全体が落ちないよう、当該
          // ドキュメントだけ除外してログに残す。
          AppLogger.error(
            'Failed to parse user ${doc.id}, skipping it',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      return members;
    });
  }

  /// 単一メンバーをリアルタイムに監視する。存在しなければ null。
  Stream<User?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        return User.fromFirestore(doc);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Failed to parse user $uid',
          tag: _logTag,
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    });
  }

  /// 自分の識別色を更新する（FR-2）。
  ///
  /// 基本設計 §2.2 の Security Rules 上、本人（uid==自分）のみ更新可。
  Future<void> updateColor(String uid, String color) {
    return _users
        .doc(uid)
        .update({'color': color, 'updatedAt': FieldValue.serverTimestamp()})
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to update color for user $uid',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }

  /// 自分の表示名を更新する（FR-2 の参加者表示に反映）。
  ///
  /// 基本設計 §2.2 の Security Rules 上、本人（uid==自分）のみ更新可。
  Future<void> updateName(String uid, String name) {
    return _users
        .doc(uid)
        .update({'name': name, 'updatedAt': FieldValue.serverTimestamp()})
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to update name for user $uid',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/models.dart';

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
    return _users
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(User.fromFirestore).toList());
  }

  /// 単一メンバーをリアルタイムに監視する。存在しなければ null。
  Stream<User?> watchUser(String uid) {
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? User.fromFirestore(doc) : null);
  }
}

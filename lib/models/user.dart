import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_serialization.dart';

/// 家族メンバー。識別色は FR-2 の予定表示に利用する。
///
/// Issue #183: メールアドレスは持たない。`users/{uid}` は uid を知っている
/// 認証済みユーザーなら誰でも読めるため（NFR-4、列挙のみ禁止）、表示に不要な
/// 個人情報を載せない方針にした。メールの正典は Firebase Auth 側にある。
final class User {
  const User({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('User document ${snapshot.id} does not exist.');
    }
    return User.fromMap(snapshot.id, data);
  }

  factory User.fromMap(String id, FirestoreData data) {
    return User(
      id: id,
      name: data['name'] as String,
      color: data['color'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      // updatedAt は serverTimestamp() 書き込みのため、サーバー確定前は
      // ローカルの現在時刻を暫定値として扱う（確定後のスナップショットで
      // 正しい値に更新される）。
      updatedAt: dateTimeFromFirestore(
        data['updatedAt'],
        'updatedAt',
        pendingWriteEstimate: DateTime.now().toUtc(),
      ),
    );
  }

  final String id;
  final String name;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'name': name,
      'color': color,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAtForFirestore(
        updatedAt,
        useServerTimestamp: useServerTimestamp,
      ),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

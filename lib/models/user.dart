import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_serialization.dart';

/// 家族メンバー。識別色は FR-2 の予定表示に利用する。
final class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
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
      email: data['email'] as String,
      color: data['color'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      updatedAt: dateTimeFromFirestore(data['updatedAt'], 'updatedAt'),
    );
  }

  final String id;
  final String name;
  final String email;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    return {
      'name': name,
      'email': email,
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
    String? email,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';

const _logTag = 'UserRepository';

/// users コレクションの参照を担う。
///
/// FR-2: 予定表示で使う家族メンバーの色・名前を提供する。
/// 基本設計 §2.2 のとおり users は個別 get のみ可（列挙禁止、Issue #89）・
/// 更新は本人のみ。
class UserRepository {
  UserRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// 指定した uid のメンバーをリアルタイムに監視する（名前昇順、Issue #89）。
  ///
  /// `users` は Security Rules で列挙を禁止しているため、コレクションを購読せず
  /// uid ごとにドキュメントを購読して束ねる。渡す uid は「自分が参加している
  /// カレンダーの `memberIds`」＝自分に見えてよいメンバーに限られる。
  /// 存在しない uid は結果に含めない。
  Stream<List<User>> watchUsers(List<String> uids) {
    if (uids.isEmpty) {
      return Stream.value(const []);
    }

    final byId = <String, User>{};
    final subscriptions = <StreamSubscription<User?>>[];
    var scheduled = false;
    late final StreamController<List<User>> controller;

    // 同じターンに複数の uid が届いても1回にまとめて流す。購読開始と同時に
    // （＝ウィジェットのビルド中に）同期的に流すと、リスナー側の再ビルドを
    // ビルド中に要求してしまうため、マイクロタスクへ逃がす。
    void emit() {
      if (scheduled || controller.isClosed) return;
      scheduled = true;
      scheduleMicrotask(() {
        scheduled = false;
        if (controller.isClosed) return;
        controller.add(
          byId.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
        );
      });
    }

    controller = StreamController<List<User>>(
      onListen: () {
        for (final uid in uids) {
          subscriptions.add(
            watchUser(uid).listen((user) {
              if (user == null) {
                byId.remove(uid);
              } else {
                byId[uid] = user;
              }
              emit();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
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

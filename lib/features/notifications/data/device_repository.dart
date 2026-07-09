import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';

const _logTag = 'DeviceRepository';

/// `users/{uid}/devices/{token}` の登録を担う（FR-5、基本設計 §3.1 / §5.2）。
///
/// 基本設計 §2.2 の Security Rules 上、本人（uid==自分）のみ読書き可。
class DeviceRepository {
  DeviceRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _firestore.collection('users').doc(uid).collection('devices');

  /// FCM トークンを upsert する。起動時取得・`onTokenRefresh` の両方から使う。
  Future<void> upsertToken({
    required String uid,
    required String token,
    required String platform,
  }) {
    return _devices(uid)
        .doc(token)
        .set({'platform': platform, 'updatedAt': FieldValue.serverTimestamp()})
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to upsert device token for user $uid',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }

  /// サインアウト時にこの端末のトークンを削除する。
  Future<void> deleteToken({required String uid, required String token}) {
    return _devices(uid).doc(token).delete().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      AppLogger.error(
        'Failed to delete device token for user $uid',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw error;
    });
  }
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../core/logger.dart';
import '../../auth/application/auth_state.dart';
import '../data/device_repository.dart';
import 'foreground_notification_presenter.dart';

const _logTag = 'Notifications';

final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (ref) => FirebaseMessaging.instance,
);

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(firestore: ref.watch(firestoreProvider));
});

/// `users/{uid}/devices/{token}.platform` に記録する現在端末の種別。
String currentDevicePlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return 'other';
  }
}

/// FCM トークンの取得・登録・サインアウト時の削除をまとめる（FR-5）。
abstract interface class DeviceRegistrationService {
  /// 現在のトークンを `users/{uid}/devices/{token}` に upsert する。
  Future<void> registerCurrentToken(String uid);

  /// サインアウト前にこの端末のトークンを削除する。
  Future<void> unregisterForSignOut(String uid);
}

class FirebaseDeviceRegistrationService implements DeviceRegistrationService {
  FirebaseDeviceRegistrationService({
    required FirebaseMessaging messaging,
    required DeviceRepository repository,
  }) : _messaging = messaging,
       _repository = repository;

  final FirebaseMessaging _messaging;
  final DeviceRepository _repository;

  @override
  Future<void> registerCurrentToken(String uid) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _repository.upsertToken(
      uid: uid,
      token: token,
      platform: currentDevicePlatform(),
    );
  }

  @override
  Future<void> unregisterForSignOut(String uid) async {
    // Security Rules は request.auth.uid == uid のみ書込を許可するため、
    // この削除は認証セッションが失われる signOut() 呼び出しより前に行う必要がある。
    final token = await _messaging.getToken();
    if (token == null) return;
    await _repository.deleteToken(uid: uid, token: token);
  }
}

final deviceRegistrationServiceProvider = Provider<DeviceRegistrationService>((
  ref,
) {
  return FirebaseDeviceRegistrationService(
    messaging: ref.watch(firebaseMessagingProvider),
    repository: ref.watch(deviceRepositoryProvider),
  );
});

/// サインイン確定後に通知権限をリクエストし、FCM トークンを登録し続ける（FR-5）。
///
/// `calendarBootstrapProvider` と同様、UI をブロックしない副作用として
/// アプリ起動時に一度 watch する想定。テストでは通常この Provider ごと
/// no-op に上書きする（実 FirebaseMessaging に触れないため）。
final notificationBootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;

  final messaging = ref.watch(firebaseMessagingProvider);

  // iOS はフォアグラウンド受信時もバナー表示させる（最小ハンドリング）。
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  final settings = await messaging.requestPermission();
  if (settings.authorizationStatus == AuthorizationStatus.denied) {
    return;
  }

  await ref.read(deviceRegistrationServiceProvider).registerCurrentToken(uid);

  final tokenSubscription = messaging.onTokenRefresh.listen((token) {
    ref
        .read(deviceRepositoryProvider)
        .upsertToken(uid: uid, token: token, platform: currentDevicePlatform());
  });
  ref.onDispose(tokenSubscription.cancel);

  // Android はフォアグラウンド時に OS が通知を自動表示しないため、ローカル通知
  // として表示する（Issue #147）。iOS / Web はプレゼンターが no-op で、上記の
  // setForegroundNotificationPresentationOptions により表示される（二重表示なし）。
  // バックグラウンド/終了時は従来どおり OS が通知を自動表示する。
  final presenter = ref.read(foregroundNotificationPresenterProvider);
  await presenter.initialize();
  final messageSubscription = FirebaseMessaging.onMessage.listen((message) {
    AppLogger.info(
      'Received foreground message ${message.messageId}',
      tag: _logTag,
    );
    presenter.show(message);
  });
  ref.onDispose(messageSubscription.cancel);
});

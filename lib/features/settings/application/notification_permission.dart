import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_state.dart';
import '../../notifications/application/notification_providers.dart';

/// 通知許可の状態（NFR-4 / FR-5 の前提）。
enum NotificationPermissionStatus {
  notDetermined('未設定'),
  granted('許可済み'),
  denied('拒否');

  const NotificationPermissionStatus(this.label);

  final String label;
}

/// 通知許可の取得・要求を抽象化する。
///
/// テストでは [StubNotificationPermissionGateway] を、実機では
/// [FirebaseNotificationPermissionGateway] を注入する（FR-5、Issue #13）。
abstract interface class NotificationPermissionGateway {
  Future<NotificationPermissionStatus> current();

  Future<NotificationPermissionStatus> request();
}

/// テスト用のスタブ。常に「未設定」を返す。
class StubNotificationPermissionGateway
    implements NotificationPermissionGateway {
  const StubNotificationPermissionGateway();

  @override
  Future<NotificationPermissionStatus> current() async =>
      NotificationPermissionStatus.notDetermined;

  @override
  Future<NotificationPermissionStatus> request() async =>
      NotificationPermissionStatus.notDetermined;
}

/// 実際の FCM/APNs 権限状態を反映するゲートウェイ（FR-5、Issue #13）。
class FirebaseNotificationPermissionGateway
    implements NotificationPermissionGateway {
  FirebaseNotificationPermissionGateway({required FirebaseMessaging messaging})
    : _messaging = messaging;

  final FirebaseMessaging _messaging;

  @override
  Future<NotificationPermissionStatus> current() async {
    final settings = await _messaging.getNotificationSettings();
    return _statusFrom(settings.authorizationStatus);
  }

  @override
  Future<NotificationPermissionStatus> request() async {
    final settings = await _messaging.requestPermission();
    return _statusFrom(settings.authorizationStatus);
  }

  NotificationPermissionStatus _statusFrom(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return NotificationPermissionStatus.granted;
      case AuthorizationStatus.denied:
        return NotificationPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return NotificationPermissionStatus.notDetermined;
    }
  }
}

final notificationPermissionGatewayProvider =
    Provider<NotificationPermissionGateway>(
      (ref) => FirebaseNotificationPermissionGateway(
        messaging: ref.watch(firebaseMessagingProvider),
      ),
    );

/// 通知許可状態を保持し、許可要求の導線を提供する。
final notificationPermissionProvider =
    AsyncNotifierProvider<
      NotificationPermissionController,
      NotificationPermissionStatus
    >(NotificationPermissionController.new);

class NotificationPermissionController
    extends AsyncNotifier<NotificationPermissionStatus> {
  @override
  Future<NotificationPermissionStatus> build() {
    return ref.watch(notificationPermissionGatewayProvider).current();
  }

  /// 通知許可をリクエストする（要求導線）。
  ///
  /// 許可が得られた場合、その場で FCM トークンを登録する（起動時に一度
  /// 拒否されたユーザーが後から本画面で許可した場合の取りこぼし防止）。
  Future<void> request() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final status = await ref
          .read(notificationPermissionGatewayProvider)
          .request();
      if (status == NotificationPermissionStatus.granted) {
        final uid = ref.read(currentUidProvider);
        if (uid != null) {
          await ref
              .read(deviceRegistrationServiceProvider)
              .registerCurrentToken(uid);
        }
      }
      return status;
    });
  }
}

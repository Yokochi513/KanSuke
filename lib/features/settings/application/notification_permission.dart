import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// 本 Issue（#12）ではスタブを提供し、実際の FCM/APNs 連携と
/// トークン登録は FCM Issue（#13）で本実装を注入する。
abstract interface class NotificationPermissionGateway {
  Future<NotificationPermissionStatus> current();

  Future<NotificationPermissionStatus> request();
}

/// #13 まで用いるスタブ。常に「未設定」を返す。
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

final notificationPermissionGatewayProvider =
    Provider<NotificationPermissionGateway>(
      (ref) => const StubNotificationPermissionGateway(),
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
  Future<void> request() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(notificationPermissionGatewayProvider).request(),
    );
  }
}

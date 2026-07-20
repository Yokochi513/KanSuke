import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// フォアグラウンド受信した FCM メッセージを通知として表示する（FR-5, Issue #147）。
///
/// Android はフォアグラウンド時に notification メッセージを OS が自動表示しない
/// ため、`onMessage` から本プレゼンターでローカル通知として表示する。
/// iOS / Web は `setForegroundNotificationPresentationOptions` 側で表示される
/// ため no-op とし、二重表示を防ぐ。
abstract interface class ForegroundNotificationPresenter {
  /// 通知チャンネルの作成等、表示前に一度だけ必要な初期化を行う。
  Future<void> initialize();

  /// 受信メッセージを通知として表示する。notification ペイロードが無ければ何もしない。
  Future<void> show(RemoteMessage message);
}

/// リマインド通知用の Android 通知チャンネル。
///
/// FCM がバックグラウンド時に使う既定チャンネルとは別に、フォアグラウンド表示
/// 専用として作成する。バナー表示（heads-up）させるため重要度は high。
const reminderNotificationChannel = AndroidNotificationChannel(
  'reminders',
  'リマインド通知',
  description: '予定のリマインド通知',
  importance: Importance.high,
);

/// Android 向け実装。`flutter_local_notifications` で通知を表示する。
class AndroidForegroundNotificationPresenter
    implements ForegroundNotificationPresenter {
  AndroidForegroundNotificationPresenter({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(reminderNotificationChannel);
  }

  @override
  Future<void> show(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _plugin.show(
      // 同一メッセージの再表示は上書きされるよう messageId から ID を導出する。
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminderNotificationChannel.id,
          reminderNotificationChannel.name,
          channelDescription: reminderNotificationChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

/// iOS / Web 等、OS 側の仕組みで表示されるプラットフォーム向けの no-op 実装。
class NoopForegroundNotificationPresenter
    implements ForegroundNotificationPresenter {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(RemoteMessage message) async {}
}

final foregroundNotificationPresenterProvider =
    Provider<ForegroundNotificationPresenter>((ref) {
      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      return isAndroid
          ? AndroidForegroundNotificationPresenter()
          : NoopForegroundNotificationPresenter();
    });

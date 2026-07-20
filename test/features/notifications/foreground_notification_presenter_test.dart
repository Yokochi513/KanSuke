import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/notifications/application/foreground_notification_presenter.dart';

void main() {
  group('AndroidForegroundNotificationPresenter', () {
    late _FakeLocalNotificationsPlugin plugin;
    late AndroidForegroundNotificationPresenter presenter;

    setUp(() {
      plugin = _FakeLocalNotificationsPlugin();
      presenter = AndroidForegroundNotificationPresenter(plugin: plugin);
    });

    test('initialize はプラグインを初期化する', () async {
      await presenter.initialize();

      expect(plugin.initializeCount, 1);
    });

    test('notification ペイロード付きメッセージをリマインドチャンネルへ表示する', () async {
      const message = RemoteMessage(
        messageId: 'message-1',
        notification: RemoteNotification(title: '買い物', body: '30分後に開始します'),
      );

      await presenter.show(message);

      expect(plugin.shownTitles, ['買い物']);
      expect(plugin.shownBodies, ['30分後に開始します']);
      final android = plugin.shownDetails.single?.android;
      expect(android?.channelId, reminderNotificationChannel.id);
    });

    test('データのみのメッセージ（notification なし）は表示しない', () async {
      const message = RemoteMessage(
        messageId: 'message-2',
        data: {'eventId': 'event-1'},
      );

      await presenter.show(message);

      expect(plugin.showCount, 0);
    });
  });

  group('foregroundNotificationPresenterProvider', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('Android ではローカル通知プレゼンターを返す', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(foregroundNotificationPresenterProvider),
        isA<AndroidForegroundNotificationPresenter>(),
      );
    });

    test('iOS では no-op プレゼンターを返す（OS 側で表示され二重にならない）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(foregroundNotificationPresenterProvider),
        isA<NoopForegroundNotificationPresenter>(),
      );
    });
  });
}

/// 実プラグインに触れず呼び出し内容だけ記録する Fake。
class _FakeLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  int initializeCount = 0;
  int showCount = 0;
  final List<String?> shownTitles = [];
  final List<String?> shownBodies = [];
  final List<NotificationDetails?> shownDetails = [];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCount++;
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCount++;
    shownTitles.add(title);
    shownBodies.add(body);
    shownDetails.add(notificationDetails);
  }
}

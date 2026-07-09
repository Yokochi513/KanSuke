import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/logger.dart';
import 'firebase_options.dart';

/// バックグラウンド/終了時に届いた FCM メッセージの最小ハンドリング（FR-5）。
///
/// 別 Isolate で実行されるため、ここで Firebase を再初期化する必要がある。
/// 通知の表示自体は OS が自動で行うため、ここでは受信ログのみ残す。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  AppLogger.info(
    'Received background message ${message.messageId}',
    tag: 'Notifications',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // NFR-3: オフライン永続化を全プラットフォームで明示的に有効化する。
  // モバイルでは既定で有効だが、Web では既定無効のため設定が必須
  // （Web は IndexedDB による単一タブ永続化として構成される）。
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  runApp(
    ProviderScope(
      observers: const [LoggingProviderObserver()],
      child: const KanSukeApp(),
    ),
  );
}

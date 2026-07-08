import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/logger.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

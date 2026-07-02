import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // NFR-3: モバイルで既定有効のオフライン永続化を構成として明示する。
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  runApp(const KanSukeApp());
}

class KanSukeApp extends StatelessWidget {
  const KanSukeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'KanSuke', home: HomePage());
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('KanSuke')),
      body: const Center(child: Text('KanSuke')),
    );
  }
}

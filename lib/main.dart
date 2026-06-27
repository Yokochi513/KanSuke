import 'package:flutter/material.dart';

void main() {
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

import 'package:flutter/material.dart';

class DayEventsScreen extends StatelessWidget {
  const DayEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日別予定一覧')),
      body: const Center(child: Text('選択日の予定を表示します')),
    );
  }
}

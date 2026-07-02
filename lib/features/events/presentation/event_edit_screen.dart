import 'package:flutter/material.dart';

class EventEditScreen extends StatelessWidget {
  const EventEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('予定編集')),
      body: const Center(child: Text('予定を作成・編集します')),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../app/routes.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('カレンダー'),
        actions: [
          IconButton(
            tooltip: '設定',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.dayEvents);
              },
              child: const Text('日別予定一覧'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.eventEdit);
              },
              child: const Text('予定を編集'),
            ),
          ],
        ),
      ),
    );
  }
}

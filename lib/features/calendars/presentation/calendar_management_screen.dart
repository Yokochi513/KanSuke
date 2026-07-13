import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../models/models.dart';
import '../application/calendar_providers.dart';
import 'calendar_edit_args.dart';

/// カレンダー管理画面（FR-8）。
///
/// 自分が参加しているカレンダーの一覧表示・新規作成と、編集画面（名前の変更・
/// メンバー管理・退出、Issue #89）への導線を提供する。カレンダーの削除はスコープ外。
class CalendarManagementScreen extends ConsumerWidget {
  const CalendarManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendarsAsync = ref.watch(myCalendarsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('カレンダー管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.calendarEdit,
          arguments: const CalendarEditArgs.create(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新規作成'),
      ),
      body: calendarsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('カレンダーを読み込めませんでした。通信環境を確認してください。')),
        data: (calendars) {
          if (calendars.isEmpty) {
            return const Center(child: Text('参加しているカレンダーがありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: calendars.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              return _CalendarTile(calendar: calendar);
            },
          );
        },
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.calendar});

  final Calendar calendar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.calendar_month_outlined),
      title: Text(calendar.name),
      subtitle: Text('参加者 ${calendar.memberIds.length}人'),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.calendarEdit,
        arguments: CalendarEditArgs.edit(calendar),
      ),
    );
  }
}

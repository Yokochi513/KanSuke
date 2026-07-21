import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../models/models.dart';
import '../../invites/presentation/join_invite_dialog.dart';
import '../application/calendar_providers.dart';
import 'calendar_edit_args.dart';

/// カレンダー管理画面（FR-8）。
///
/// 自分が参加しているカレンダーの一覧表示・新規作成と、編集画面（名前の変更・
/// メンバー管理・退出、Issue #89／カレンダーの削除、Issue #169）への導線を提供する。
class CalendarManagementScreen extends ConsumerWidget {
  const CalendarManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendarsAsync = ref.watch(myCalendarsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('カレンダー管理'),
        actions: [
          // FR-9: リンクを踏んでアプリが起動しない環境（Web など）でも参加できる
          // ように、リンクを貼り付ける導線を置く（Issue #90）。
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: '招待リンクで参加',
            onPressed: () => JoinInviteDialog.show(context),
          ),
        ],
      ),
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
        data: (_) {
          // 表示順は端末ローカルの並び順を反映したもの（Issue #168）。
          final calendars = ref.watch(orderedCalendarsProvider);
          if (calendars.isEmpty) {
            return const Center(child: Text('参加しているカレンダーがありません'));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: calendars.length,
            onReorder: (oldIndex, newIndex) {
              final ids = [for (final c in calendars) c.id];
              // ReorderableListView の newIndex は移動元を抜く前の位置で渡る。
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              ids.insert(newIndex, ids.removeAt(oldIndex));
              unawaited(ref.read(calendarOrderProvider.notifier).save(ids));
            },
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              return _CalendarTile(
                key: ValueKey(calendar.id),
                calendar: calendar,
              );
            },
          );
        },
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({super.key, required this.calendar});

  final Calendar calendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(calendar.name),
          subtitle: Text('参加者 ${calendar.memberIds.length}人'),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.calendarEdit,
            arguments: CalendarEditArgs.edit(calendar),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

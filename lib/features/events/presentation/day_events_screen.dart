import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../core/color_utils.dart';
import '../../../models/models.dart';
import '../../users/application/user_providers.dart';
import '../application/event_providers.dart';
import 'event_edit_args.dart';
import 'event_type_badge.dart';

/// 日別予定一覧（FR-1 / FR-2 / FR-3、基本設計 §6.1）。
///
/// 選択日の予定を所有者色・種別バッジ・時刻付きで表示し、各項目や新規作成から
/// 予定編集画面（#11）へ遷移する。対象日はルート引数（[DateTime]）で受け取る。
class DayEventsScreen extends ConsumerWidget {
  const DayEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final day = arg is DateTime
        ? DateUtils.dateOnly(arg)
        : DateUtils.dateOnly(DateTime.now());
    final nextDay = day.add(const Duration(days: 1));

    final eventsAsync = ref.watch(
      eventsInRangeProvider((start: day, end: nextDay)),
    );
    final membersById = ref.watch(membersByIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${_formatDate(day)} の予定')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.eventEdit,
          arguments: EventEditArgs.create(day),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新規作成'),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('予定を読み込めませんでした。通信環境を確認してください。')),
        data: (events) {
          if (events.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              return _EventTile(
                event: event,
                owner: membersById[event.ownerId],
                membersById: membersById,
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime day) =>
      '${day.year}/${_two(day.month)}/${_two(day.day)}';
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.owner,
    required this.membersById,
  });

  final Event event;
  final User? owner;
  final Map<String, User> membersById;

  @override
  Widget build(BuildContext context) {
    final memberColors = event.memberIds
        .map((id) => colorFromHex(membersById[id]?.color ?? ''))
        .toList();
    final participantsLabel = _participantsLabel(event);
    return ListTile(
      leading: _MemberDots(colors: memberColors),
      title: Text(event.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_scheduleLabel(event)),
          if (participantsLabel != null)
            Text(
              '参加: $participantsLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: EventTypeBadge(event.type),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.eventEdit,
        arguments: EventEditArgs.edit(event),
      ),
    );
  }

  /// 参加者名（所有者を除く）を「・」区切りで返す。参加者がいなければ null。
  String? _participantsLabel(Event event) {
    final names = event.participantIds
        .where((id) => id != event.ownerId)
        .map((id) => membersById[id]?.name)
        .whereType<String>()
        .toList();
    if (names.isEmpty) return null;
    return names.join('・');
  }

  String _scheduleLabel(Event event) {
    final ownerName = owner?.name;
    final ownerLabel = ownerName == null ? '' : '・$ownerName';
    if (event.allDay) {
      return '終日$ownerLabel';
    }
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    return '${_two(start.hour)}:${_two(start.minute)}'
        '〜${_two(end.hour)}:${_two(end.minute)}$ownerLabel';
  }
}

/// 参加メンバー（所有者を含む）を色付きドットで並べる（FR-2、参加者の可視化）。
///
/// 一目で誰が参加しているか把握できるよう、所有者色 1 色だけに頼らず全員分表示する。
class _MemberDots extends StatelessWidget {
  const _MemberDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (final color in colors)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available,
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 8),
          const Text('予定はありません'),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../models/models.dart';
import '../application/calendar_providers.dart';

/// 月表示・日別一覧の AppBar タイトルに置く、カレンダー切替ボタン（FR-8）。
///
/// タップでボトムシートを開き、自分が参加しているカレンダーの中から表示対象を
/// 選ぶ。Issue #170 で複数選択に対応し、選んだカレンダーの予定を重ねて表示する。
/// 未選択なら一覧の先頭（アカウント作成時に自動生成される個人カレンダー）を
/// 表示する。シート下部から管理画面へも遷移できる。
class CalendarSwitcherTitle extends ConsumerWidget {
  const CalendarSwitcherTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCalendars = ref.watch(visibleCalendarsProvider);

    return InkWell(
      onTap: () => _openSwitcher(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                calendarSwitcherLabel(visibleCalendars),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Future<void> _openSwitcher(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => const _CalendarSwitcherSheet(),
    );
  }
}

/// タイトルに出すラベル（Issue #170）。
///
/// 1 件なら従来どおりカレンダー名、複数なら「先頭の名前 ほかN件」で、いま何を
/// 重ねて見ているかを 1 行で示す。まだ何も解決できていない間は「カレンダー」。
String calendarSwitcherLabel(List<Calendar> visibleCalendars) {
  if (visibleCalendars.isEmpty) return 'カレンダー';
  if (visibleCalendars.length == 1) return visibleCalendars.first.name;
  return '${visibleCalendars.first.name} ほか${visibleCalendars.length - 1}件';
}

/// カレンダーの表示 ON/OFF を選ぶボトムシート（Issue #170）。
///
/// チェックボックスの複数選択。上限（[kMaxVisibleCalendars]）に達したら未選択の
/// 行を無効化して超過を防ぎ、最後の 1 件は外せないようにして「何も表示されない」
/// 状態を作らせない。
class _CalendarSwitcherSheet extends ConsumerWidget {
  const _CalendarSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(orderedCalendarsProvider);
    final visibleIds = ref.watch(visibleCalendarIdsProvider);
    final canAdd = canAddVisibleCalendar(visibleIds);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('表示するカレンダー', style: theme.textTheme.titleSmall),
                  ),
                  Text(
                    '${visibleIds.length}/$kMaxVisibleCalendars',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final calendar in calendars)
              _CalendarCheckTile(
                calendar: calendar,
                visibleIds: visibleIds,
                // 上限に達したら未選択の行は選べない（超過を UI で防ぐ）。
                // 最後の 1 件は外せない（全非表示を作らせない）。
                enabled: visibleIds.contains(calendar.id)
                    ? visibleIds.length > 1
                    : canAdd,
              ),
            if (!canAdd)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '同時に表示できるのは$kMaxVisibleCalendars件までです。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('カレンダーを管理'),
              onTap: () {
                // シートを閉じた後にこの widget の context は使えないため、
                // Navigator を先に取っておいてから閉じる→遷移する。
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.pushNamed(AppRoutes.calendarManagement);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarCheckTile extends ConsumerWidget {
  const _CalendarCheckTile({
    required this.calendar,
    required this.visibleIds,
    required this.enabled,
  });

  final Calendar calendar;
  final List<String> visibleIds;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      value: visibleIds.contains(calendar.id),
      title: Text(calendar.name),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: enabled
          ? (_) {
              // 保存（Issue #167 / #170）は待たずに反映する。状態は同期的に変わり、
              // シートは開いたままなので続けて他のカレンダーも選べる。
              unawaited(
                ref
                    .read(calendarSelectionProvider.notifier)
                    .setVisible(
                      toggledVisibleCalendarIds(visibleIds, calendar.id),
                    ),
              );
            }
          : null,
    );
  }
}

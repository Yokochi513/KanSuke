import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../models/models.dart';
import '../application/calendar_providers.dart';

/// 月表示・日別一覧の AppBar タイトルに置く、カレンダー切替ボタン（FR-8）。
///
/// タップでボトムシートを開き、自分が参加しているカレンダーの中から表示対象を
/// 選ぶ。未選択なら一覧の先頭（アカウント作成時に自動生成される個人カレンダー）を
/// 表示する。シート下部から管理画面へも遷移できる。
class CalendarSwitcherTitle extends ConsumerWidget {
  const CalendarSwitcherTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 管理画面で並べ替えた順を切替 UI にも反映する（Issue #168）。
    final calendars = ref.watch(orderedCalendarsProvider);
    final selectedId = ref.watch(selectedCalendarIdProvider);
    final selectedName = calendars
        .cast<Calendar?>()
        .firstWhere((c) => c?.id == selectedId, orElse: () => null)
        ?.name;

    return InkWell(
      onTap: () => _openSwitcher(context, ref, calendars, selectedId),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selectedName ?? 'カレンダー',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Future<void> _openSwitcher(
    BuildContext context,
    WidgetRef ref,
    List<Calendar> calendars,
    String selectedId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final calendar in calendars)
                ListTile(
                  leading: Icon(
                    calendar.id == selectedId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(calendar.name),
                  onTap: () {
                    // 保存（Issue #167）は待たずに閉じる。状態は同期的に反映される。
                    unawaited(
                      ref
                          .read(calendarSelectionProvider.notifier)
                          .select(calendar.id),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('カレンダーを管理'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(context, AppRoutes.calendarManagement);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

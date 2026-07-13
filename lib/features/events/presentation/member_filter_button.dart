import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/color_utils.dart';
import '../application/event_filter.dart';

/// 参加者フィルタを開く AppBar アクション（Issue #78、FR-2 補完）。
///
/// タップでボトムシートを開き、表示中カレンダーの参加者から絞り込み対象を
/// 複数選択できる。絞り込み中はアイコンを強調し、選択人数をバッジで示す。
/// 月表示・日別一覧のどちらの AppBar にも置ける。
class MemberFilterButton extends ConsumerWidget {
  const MemberFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(memberFilterProvider);
    final active = selected.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: '参加者で絞り込み',
      onPressed: () => _openFilterSheet(context),
      icon: Badge(
        // 絞り込み中は選択人数を出し、何人で絞っているか一目でわかるようにする。
        isLabelVisible: active,
        label: Text('${selected.length}'),
        child: Icon(
          active ? Icons.filter_alt : Icons.filter_alt_outlined,
          color: active ? scheme.primary : null,
        ),
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => const _MemberFilterSheet(),
    );
  }
}

/// 参加者フィルタの選択シート（Issue #78）。
///
/// 表示中カレンダーの参加者を一覧し、チェックで絞り込み対象を選ぶ（複数選択可）。
/// いずれかを含む予定だけが月表示・日別一覧に表示される。未選択なら全件表示。
class _MemberFilterSheet extends ConsumerWidget {
  const _MemberFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(filterableMembersProvider);
    final selected = ref.watch(memberFilterProvider);
    final notifier = ref.read(memberFilterProvider.notifier);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '参加者で絞り込み',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // 未選択時は「全件表示中」なので解除ボタンは無効にする。
                TextButton(
                  onPressed: selected.isEmpty ? null : notifier.clear,
                  child: const Text('すべて表示'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('参加者がいません')),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final member in members)
                    CheckboxListTile(
                      value: selected.contains(member.id),
                      onChanged: (_) => notifier.toggle(member.id),
                      secondary: _MemberColorDot(color: member.color),
                      title: Text(member.name),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// メンバー識別色のドット（FR-2）。誰を絞り込むか色でも判別できるようにする。
class _MemberColorDot extends StatelessWidget {
  const _MemberColorDot({required this.color});

  final String color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colorFromHex(color),
        shape: BoxShape.circle,
      ),
    );
  }
}

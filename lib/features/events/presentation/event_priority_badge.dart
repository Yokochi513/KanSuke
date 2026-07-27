import 'package:flutter/material.dart';

import '../../../models/models.dart';

/// 優先度の目印（Issue #176、FR-1 / FR-4）。
///
/// 既定（[defaultEventPriority]）のままの予定には**何も出さない**。ほとんどの予定は
/// 既定のままなので、常に出すと目印がノイズになって「わざわざ動かした予定」が
/// 埋もれてしまう。既定から動かしたものだけを示すことで、月表示の並びが普段と
/// 違う理由が読み取れるようにする。
class EventPriorityBadge extends StatelessWidget {
  const EventPriorityBadge(this.priority, {super.key});

  final int priority;

  @override
  Widget build(BuildContext context) {
    if (priority == defaultEventPriority) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // 重要度を上げた予定（1〜4）は目を引く色、下げた予定（6〜10）は控えめな色。
    final raised = priority < defaultEventPriority;
    final color = raised ? scheme.error : scheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '優先度$priority',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// 月表示の帯のタイトルに付ける優先度の目印（Issue #176）。
///
/// 帯は高さ 16px しかなく、[EventPriorityBadge] のようなチップを差し込む余裕が
/// ない。またマージ帯（`MergedEventBar`）はタイトル文字列の実測でチップ右端を
/// 求めている（Issue #125）ため、ウィジェットを足すと計算と描画がずれる。
/// **タイトル文字列の先頭に付ける**ことで、既存の測り方をそのまま使える。
///
/// 既定（[defaultEventPriority]）のままなら [title] をそのまま返す。
String eventBarTitleWithPriority(String title, int priority) {
  if (priority == defaultEventPriority) return title;
  return '[$priority] $title';
}

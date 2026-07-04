import 'package:flutter/material.dart';

import '../../../models/models.dart';

/// 種別バッジ（FR-3、基本設計 §6.3）。
///
/// 確定＝塗りつぶし、仮＝枠線・半透明で区別する。
class EventTypeBadge extends StatelessWidget {
  const EventTypeBadge(this.type, {super.key});

  final EventType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = type == EventType.confirmed;
    final label = confirmed ? '確定' : '仮';
    final color = confirmed ? scheme.primary : scheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: confirmed ? color : color.withValues(alpha: 0.12),
        border: confirmed ? null : Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: confirmed ? scheme.onPrimary : color,
        ),
      ),
    );
  }
}

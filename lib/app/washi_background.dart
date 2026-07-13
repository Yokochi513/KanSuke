import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 和紙の地に見せる背景。
///
/// 画像アセットを持たずに済むよう、繊維を模した短い線を [CustomPainter] で
/// 描く。乱数は固定シードで引くため、再ビルドしても模様は動かない。
/// 全画面の背後に敷く前提で、[ThemeData.scaffoldBackgroundColor] は透明。
class WashiBackground extends StatelessWidget {
  const WashiBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = KanSukeColors.of(context);

    return ColoredBox(
      color: colors.washiBase,
      child: Stack(
        children: [
          // 前面の画面が再描画されても繊維を描き直さないよう層を分ける。
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WashiFiberPainter(colors.washiFiber),
                isComplex: true,
                willChange: false,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _WashiFiberPainter extends CustomPainter {
  const _WashiFiberPainter(this.fiberColor);

  final Color fiberColor;

  /// 1px^2 あたりの繊維本数。少ないと紙ではなく引っかき傷に見えるので、
  /// 細かく多めに散らし、代わりに 1 本ずつの濃度を落とす。
  static const double _density = 1 / 1100;

  /// 端末を変えても模様が同じになるよう固定する。
  static const int _seed = 20240710;

  /// 大画面で描画本数が際限なく増えないための上限。
  static const int _maxFibers = 2400;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final random = math.Random(_seed);
    final paint = Paint()
      ..color = fiberColor
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final count = (size.width * size.height * _density).round().clamp(
      0,
      _maxFibers,
    );

    for (var i = 0; i < count; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      // 繊維の向きは無作為、長さは 2〜9px 程度に散らす。
      final angle = random.nextDouble() * math.pi;
      final length = 2 + random.nextDouble() * 7;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WashiFiberPainter oldDelegate) =>
      oldDelegate.fiberColor != fiberColor;
}

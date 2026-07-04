import 'package:flutter/material.dart';

/// `#RRGGBB` 形式の識別色（FR-2）を [Color] に変換する。
///
/// 不正な文字列はフォールバック色にする（表示を止めないため）。
Color colorFromHex(String hex, {Color fallback = const Color(0xFF9E9E9E)}) {
  final normalized = hex.replaceFirst('#', '').trim();
  if (normalized.length != 6) {
    return fallback;
  }
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return fallback;
  }
  return Color(0xFF000000 | value);
}

/// [Color] を `#RRGGBB` 形式（FR-2 の識別色）へ変換する。
String hexFromColor(Color color) {
  String channel(double component) =>
      (component * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'
      .toUpperCase();
}

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

/// [background] の上に重ねても判読できる文字色（黒 or 白）を返す。
///
/// 識別色は設定で自由に変えられるため（FR-2）、テーマ固定の文字色だと明るい色
/// （例: 水色 #81D4FA）で白文字が埋もれる（Issue #106 / #133）。背景の相対輝度
/// から明暗を判定し、コントラストの高い方を選ぶ。
///
/// しきい値は Flutter の [ThemeData.estimateBrightnessForColor] と同じ 0.15。
/// 黒文字と白文字のコントラスト比が逆転する相対輝度（約 0.179）に近く、
/// 「どちらがより読めるか」の分岐点として妥当なため。
Color readableTextColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// [Color] を `#RRGGBB` 形式（FR-2 の識別色）へ変換する。
String hexFromColor(Color color) {
  String channel(double component) =>
      (component * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'
      .toUpperCase();
}

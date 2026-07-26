import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/color_utils.dart';

void main() {
  group('readableTextColor（Issue #133）', () {
    test('明るい識別色には黒文字を返す', () {
      // 水色 #81D4FA・黄色 #FFEB3B のような高明度の帯で白文字だと埋もれる。
      expect(readableTextColor(const Color(0xFF81D4FA)), Colors.black);
      expect(readableTextColor(const Color(0xFFFFEB3B)), Colors.black);
      expect(readableTextColor(Colors.white), Colors.black);
    });

    test('暗い識別色には白文字を返す', () {
      expect(readableTextColor(const Color(0xFF1565C0)), Colors.white);
      expect(readableTextColor(const Color(0xFF2E7D32)), Colors.white);
      expect(readableTextColor(Colors.black), Colors.white);
    });
  });
}

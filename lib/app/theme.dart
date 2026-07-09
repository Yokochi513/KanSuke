import 'package:flutter/material.dart';

abstract final class MemberColors {
  static const palette = <Color>[
    Color(0xFF1565C0),
    Color(0xFFD84315),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFC2185B),
    Color(0xFFFDD835),
  ];
}

ThemeData buildKanSukeTheme() {
  const primaryColor = Color(0xFF1565C0);

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: true),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'settings.theme_mode';

/// 表示テーマの選択（端末に合わせる／明るい／暗い）を保持する。
///
/// 端末ローカルの設定なので Firestore ではなく [SharedPreferences] に保存し、
/// 家族の他のメンバーには影響させない。読み込み前・読み込み失敗時は
/// [ThemeMode.system] として扱う（[resolvedThemeModeProvider]）。
final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// 実際に [MaterialApp] へ渡す [ThemeMode]。読み込み中・失敗時は端末設定に従う。
final resolvedThemeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeModeProvider).value ?? ThemeMode.system;
});

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return themeModeFromName(prefs.getString(_themeModeKey));
  }

  /// テーマを切り替えて保存する。
  Future<void> select(ThemeMode mode) async {
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }
}

/// 保存済みの文字列を [ThemeMode] に戻す。未保存・未知の値は端末設定に従う。
ThemeMode themeModeFromName(String? name) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.system,
  );
}

/// 設定画面に出すラベル。横並びのボタンに収まるよう短くする。
extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => '自動',
    ThemeMode.light => '和紙',
    ThemeMode.dark => '墨',
  };

  IconData get icon => switch (this) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}

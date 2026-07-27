import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _widgetAppearanceKey = 'settings.widget_appearance';

/// ホーム画面ウィジェットの外観（Issue #127 フォローアップ）。
///
/// 名前（[name]）はそのままペイロードへ載せ、Android 側 `WidgetAppearance` が
/// 同じ文字列で受ける。値を変えるときは Kotlin 側も揃えること。
enum WidgetAppearance {
  /// 端末のダークモード設定に従う（既定）。
  system,

  /// 和紙（ライト）で固定する。
  light,

  /// 墨（ダーク）で固定する。
  dark,

  /// 地を敷かず壁紙を透かす。文字色は端末のダークモード設定に従う。
  transparent,
}

/// ウィジェットの外観の設定を保持する。
///
/// アプリ本体の表示テーマ（[themeModeProvider]）とは別に持つ。ホーム画面の
/// 壁紙に合わせたいという要求はアプリ内の見た目と一致しないため。
/// 端末ローカルの設定なので Firestore ではなく [SharedPreferences] に保存し、
/// 家族の他のメンバーには影響させない。読み込み前・読み込み失敗時は
/// [WidgetAppearance.system] として扱う（[resolvedWidgetAppearanceProvider]）。
final widgetAppearanceProvider =
    AsyncNotifierProvider<WidgetAppearanceController, WidgetAppearance>(
      WidgetAppearanceController.new,
    );

/// 実際にウィジェットへ渡す外観。読み込み中・失敗時は端末設定に従う。
final resolvedWidgetAppearanceProvider = Provider<WidgetAppearance>((ref) {
  return ref.watch(widgetAppearanceProvider).value ?? WidgetAppearance.system;
});

class WidgetAppearanceController extends AsyncNotifier<WidgetAppearance> {
  @override
  Future<WidgetAppearance> build() async {
    final prefs = await SharedPreferences.getInstance();
    return widgetAppearanceFromName(prefs.getString(_widgetAppearanceKey));
  }

  /// 外観を切り替えて保存する。
  ///
  /// ウィジェットへの反映は [HomeWidgetSync] が担う（この設定を含むペイロードを
  /// 書き直すと、Android 側が新しい外観で描き直す）。
  Future<void> select(WidgetAppearance appearance) async {
    // 保存の完了を待たずに反映し、切り替えを即座に見せる。
    state = AsyncData(appearance);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_widgetAppearanceKey, appearance.name);
  }
}

/// 保存済みの文字列を [WidgetAppearance] に戻す。未保存・未知の値は端末設定に従う。
WidgetAppearance widgetAppearanceFromName(String? name) {
  return WidgetAppearance.values.firstWhere(
    (appearance) => appearance.name == name,
    orElse: () => WidgetAppearance.system,
  );
}

/// 設定画面に出すラベル。横並びのボタンに収まるよう短くする。
extension WidgetAppearanceLabel on WidgetAppearance {
  String get label => switch (this) {
    WidgetAppearance.system => '自動',
    WidgetAppearance.light => '和紙',
    WidgetAppearance.dark => '墨',
    WidgetAppearance.transparent => '透過',
  };

  IconData get icon => switch (this) {
    WidgetAppearance.system => Icons.brightness_auto_outlined,
    WidgetAppearance.light => Icons.light_mode_outlined,
    WidgetAppearance.dark => Icons.dark_mode_outlined,
    WidgetAppearance.transparent => Icons.gradient_outlined,
  };
}

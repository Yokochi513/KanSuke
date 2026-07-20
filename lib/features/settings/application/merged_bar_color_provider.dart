import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/color_utils.dart';

const _mergedBarColorKey = 'settings.merged_bar_color';

/// まとめ帯（マージ帯・丸マーク帯）の地色の設定（Issue #112 フォローアップ）。
///
/// `#RRGGBB` 形式で保持し、null はテーマ既定（[KanSukeColors.mergedBar] の
/// ライト/ダークそれぞれの既定色）を意味する。端末ローカルの設定なので
/// Firestore ではなく [SharedPreferences] に保存し、家族の他のメンバーには
/// 影響させない。読み込み前・読み込み失敗時はテーマ既定として扱う
/// （[resolvedMergedBarColorProvider]）。
final mergedBarColorProvider =
    AsyncNotifierProvider<MergedBarColorController, String?>(
      MergedBarColorController.new,
    );

/// 実際にテーマ構築（`buildKanSukeTheme`）へ渡す帯の地色。
/// null（未設定・読み込み中・失敗時）はテーマ既定に従う。
final resolvedMergedBarColorProvider = Provider<Color?>((ref) {
  final hex = ref.watch(mergedBarColorProvider).value;
  if (hex == null) {
    return null;
  }
  return colorFromHex(hex);
});

class MergedBarColorController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mergedBarColorKey);
  }

  /// 帯の地色を保存する。null でテーマ既定へ戻す。
  Future<void> select(String? hex) async {
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(hex);
    final prefs = await SharedPreferences.getInstance();
    if (hex == null) {
      await prefs.remove(_mergedBarColorKey);
    } else {
      await prefs.setString(_mergedBarColorKey, hex);
    }
  }
}

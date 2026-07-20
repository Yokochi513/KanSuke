import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _multiMemberEventDisplayKey = 'settings.multi_member_event_display';

/// 月表示で複数人が参加する予定の色の見せ方（Issue #112、FR-2 / FR-4）。
enum MultiMemberEventDisplay {
  /// タイトルの右に参加者色の丸（ドット）を並べる。帯の地色は中立色にする。
  dots,

  /// 帯を参加者の色で縦に塗り分ける（従来表示）。
  split,
}

/// 複数人予定の表示方法の設定（Issue #112）。
///
/// 帯を参加者色で塗り分ける従来表示は 3 人以上で細切れになり見にくいという
/// フィードバックから、タイトル右に参加者色の丸を並べる [dots] を選べるように
/// する。既定は従来の塗り分け（[split]）のまま変えない。端末ローカルの設定
/// なので Firestore ではなく [SharedPreferences] に保存し、家族の他のメンバー
/// には影響させない。読み込み前・読み込み失敗時は既定（[split]）として扱う
/// （[resolvedMultiMemberEventDisplayProvider]）。
final multiMemberEventDisplayProvider =
    AsyncNotifierProvider<
      MultiMemberEventDisplayController,
      MultiMemberEventDisplay
    >(MultiMemberEventDisplayController.new);

/// 実際に月表示へ渡す表示方法。読み込み中・失敗時は既定（色分け）に従う。
final resolvedMultiMemberEventDisplayProvider =
    Provider<MultiMemberEventDisplay>((ref) {
      return ref.watch(multiMemberEventDisplayProvider).value ??
          MultiMemberEventDisplay.split;
    });

class MultiMemberEventDisplayController
    extends AsyncNotifier<MultiMemberEventDisplay> {
  @override
  Future<MultiMemberEventDisplay> build() async {
    final prefs = await SharedPreferences.getInstance();
    return multiMemberEventDisplayFromName(
      prefs.getString(_multiMemberEventDisplayKey),
    );
  }

  /// 表示方法を切り替えて保存する。
  Future<void> select(MultiMemberEventDisplay display) async {
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(display);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_multiMemberEventDisplayKey, display.name);
  }
}

/// 保存済みの文字列を [MultiMemberEventDisplay] に戻す。未保存・未知の値は
/// 既定（色分け）として扱う。
MultiMemberEventDisplay multiMemberEventDisplayFromName(String? name) {
  return MultiMemberEventDisplay.values.firstWhere(
    (display) => display.name == name,
    orElse: () => MultiMemberEventDisplay.split,
  );
}

/// 設定画面に出すラベル。横並びのボタンに収まるよう短くする。
extension MultiMemberEventDisplayLabel on MultiMemberEventDisplay {
  String get label => switch (this) {
    MultiMemberEventDisplay.dots => '丸マーク',
    MultiMemberEventDisplay.split => '色分け',
  };

  IconData get icon => switch (this) {
    MultiMemberEventDisplay.dots => Icons.more_horiz,
    MultiMemberEventDisplay.split => Icons.view_week_outlined,
  };
}

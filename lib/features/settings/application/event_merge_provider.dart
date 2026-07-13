import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _eventMergeEnabledKey = 'settings.event_merge_enabled';

/// 月表示で同名・期間が連なる予定を見た目上 1 本に束ねる（マージ表示）かどうか
/// の設定（Issue #76、FR-2 / FR-4）。
///
/// マージは表示上の導出のみで Firestore のデータは変えないが、暗黙グルーピングの
/// 誤爆に備えた保険として ON/OFF を切り替えられるようにする。既定は ON。
/// 端末ローカルの設定なので Firestore ではなく [SharedPreferences] に保存し、
/// 家族の他のメンバーには影響させない。読み込み前・読み込み失敗時は ON として
/// 扱う（[resolvedEventMergeEnabledProvider]）。
final eventMergeEnabledProvider =
    AsyncNotifierProvider<EventMergeController, bool>(EventMergeController.new);

/// 実際に月表示へ渡すマージ表示の ON/OFF。読み込み中・失敗時は既定（ON）に従う。
final resolvedEventMergeEnabledProvider = Provider<bool>((ref) {
  return ref.watch(eventMergeEnabledProvider).value ?? true;
});

class EventMergeController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_eventMergeEnabledKey) ?? true;
  }

  /// マージ表示の ON/OFF を切り替えて保存する。
  Future<void> setEnabled(bool enabled) async {
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_eventMergeEnabledKey, enabled);
  }
}

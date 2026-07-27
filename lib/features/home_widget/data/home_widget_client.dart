import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/logger.dart';

/// ペイロードを置く SharedPreferences のキー。Android 側と揃えること。
const String homeWidgetPayloadKey = 'kansuke.widget.payload';

/// ウィジェットプロバイダの完全修飾クラス名。`updateWidget` の宛先。
///
/// 今日・明日のリスト（[homeWidgetListProvider]）と月表示
/// （[homeWidgetMonthProvider]）の 2 種類を提供しており、同じペイロードを両方が読む。
const String homeWidgetListProvider =
    'com.kansuke.kansuke.KanSukeWidgetProvider';
const String homeWidgetMonthProvider =
    'com.kansuke.kansuke.KanSukeMonthWidgetProvider';

/// ホーム画面ウィジェットへの書き込み口（Issue #127）。
///
/// プラグイン呼び出しをここに閉じ込め、テストから差し替えられるようにする。
abstract interface class HomeWidgetClient {
  /// ペイロードを保存し、ウィジェットの再描画を促す。
  Future<void> push(String payload);
}

/// `home_widget` プラグイン経由の実装（Android のみ）。
class PluginHomeWidgetClient implements HomeWidgetClient {
  const PluginHomeWidgetClient();

  @override
  Future<void> push(String payload) async {
    await HomeWidget.saveWidgetData<String>(homeWidgetPayloadKey, payload);
    // 置かれていないウィジェットへの更新要求は、対象が 0 個の broadcast になる
    // だけで害はない。どちらが置かれているかは調べずに両方へ流す。
    await HomeWidget.updateWidget(qualifiedAndroidName: homeWidgetListProvider);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: homeWidgetMonthProvider,
    );
  }
}

/// ウィジェットを持たないプラットフォーム（iOS / Web / テスト）向けの何もしない実装。
class NoopHomeWidgetClient implements HomeWidgetClient {
  const NoopHomeWidgetClient();

  @override
  Future<void> push(String payload) async {}
}

/// 例外を握りつぶしてログに残すデコレータ。
///
/// ウィジェットの更新は付随的な処理なので、失敗してもアプリの表示は止めない。
class LoggingHomeWidgetClient implements HomeWidgetClient {
  const LoggingHomeWidgetClient(this._delegate);

  final HomeWidgetClient _delegate;

  @override
  Future<void> push(String payload) async {
    try {
      await _delegate.push(payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to update the home screen widget',
        tag: 'HomeWidget',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// ホーム画面ウィジェットの更新口。Android 以外では何もしない。
///
/// Issue #127 では Android のみを対象にした。iOS（WidgetKit）は別 Issue。
final homeWidgetClientProvider = Provider<HomeWidgetClient>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const NoopHomeWidgetClient();
  }
  return const LoggingHomeWidgetClient(PluginHomeWidgetClient());
});

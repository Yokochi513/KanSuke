import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリ全体の簡易ロガー。
///
/// `dart:developer` 経由で出力するため、DevTools の Logging パネルと
/// `flutter run` のターミナル出力の両方から確認できる。障害調査を容易に
/// するため、Firestore の読み書きやストリームのエラーは握りつぶさず
/// 必ずここを通して記録する（エラー内容自体はユーザーには出さない）。
class AppLogger {
  const AppLogger._();

  static void error(
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'KanSuke.$tag',
      error: error,
      stackTrace: stackTrace,
      level: 1000, // SEVERE
    );
  }

  static void info(String message, {required String tag}) {
    developer.log(message, name: 'KanSuke.$tag', level: 800); // INFO
  }
}

/// 個別のリポジトリでログを仕込み忘れた Provider のエラーも取りこぼさない
/// ための保険。`main.dart` の `ProviderScope` に登録して全 Provider を監視する。
final class LoggingProviderObserver extends ProviderObserver {
  const LoggingProviderObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    AppLogger.error(
      'Provider ${context.provider.name ?? context.provider.runtimeType} failed',
      tag: 'Provider',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

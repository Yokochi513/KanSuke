import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリ唯一の Navigator への参照。
///
/// 画面の外（招待リンクでの起動、FR-9 / Issue #90）から画面遷移を起こすために使う。
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(),
);

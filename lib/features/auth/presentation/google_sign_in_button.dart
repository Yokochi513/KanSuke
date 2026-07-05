/// Google サインインボタン。
///
/// モバイル/デスクトップは命令的な `authenticate()` を使う自前ボタン、
/// Web は GIS の `renderButton()` を使う。プラットフォームごとに実装を
/// 条件付きインポートで切り替える。
library;

export 'google_sign_in_button_io.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart';

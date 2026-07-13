/// 招待リンク（FR-9 / Issue #90）の URL 規約。
///
/// アプリを起動するリンクは `kansuke://invite?token=<token>` とする。カスタム
/// スキームにするのは、家庭内配布（TestFlight / APK 直配布）で Universal Links /
/// App Links に必要なドメイン所有権の検証を用意できないため。
///
/// Web ビルドでは同じアプリが `http(s)` で開かれるため、`?token=` が付いた URL を
/// 同等に受け付ける（Web はホスティング先のパスを固定できないので、パスは問わない）。
library;

/// 招待リンクのスキーム。
const String inviteLinkScheme = 'kansuke';

/// 招待リンクのホスト部（`kansuke://invite`）。
const String inviteLinkHost = 'invite';

/// トークンを載せるクエリパラメータ名。
const String inviteTokenQueryParameter = 'token';

/// 共有用の招待リンクを組み立てる。
Uri buildInviteLink(String token) {
  return Uri(
    scheme: inviteLinkScheme,
    host: inviteLinkHost,
    queryParameters: {inviteTokenQueryParameter: token},
  );
}

/// アプリを起動した URI から招待トークンを取り出す。招待リンクでなければ null。
///
/// - `kansuke://invite?token=...`（iOS / Android）
/// - `http(s)://<任意>?token=...`（Web。パスは問わない）
String? parseInviteToken(Uri uri) {
  final token = uri.queryParameters[inviteTokenQueryParameter]?.trim();
  if (token == null || token.isEmpty) {
    return null;
  }
  if (uri.scheme == inviteLinkScheme) {
    return uri.host == inviteLinkHost ? token : null;
  }
  return (uri.scheme == 'http' || uri.scheme == 'https') ? token : null;
}

/// 手で貼り付けられた招待リンク（またはトークン単体）からトークンを取り出す。
///
/// Web ではカスタムスキームのリンクをブラウザから開けず、リンクを踏んでアプリが
/// 起動する経路が使えない。また iOS / Android でも、リンクをそのまま開けない
/// メッセージアプリ経由で受け取ることがある。貼り付けでの参加はどの環境でも
/// 成立する受け口として用意する（FR-9 / Issue #90）。
String? parseInvitePaste(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    return parseInviteToken(uri);
  }
  // スキームが無ければトークン単体を貼り付けたものとして扱う。
  return text;
}

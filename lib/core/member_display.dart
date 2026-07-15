import '../models/models.dart';

/// 退会済み（`users/{uid}` が無い）メンバーの表示名（Issue #102）。
///
/// 共有カレンダーの予定には、退会した uid が参加者として残る。名前を引けない
/// メンバーをこのラベルにフォールバックすることで、予定一覧・月表示（FR-2 の
/// 参加者表示）が壊れず、誰の枠かも「退会済み」と分かるようにする。識別色は
/// 引けないため、`colorFromHex('')` のグレー（既定フォールバック）で表示する。
const deactivatedMemberName = '退会したメンバー';

/// メンバーの表示名を返す。ドキュメントが無い（退会済み）／名前が空なら
/// [deactivatedMemberName] にフォールバックする（Issue #102）。
String memberDisplayName(User? member) {
  final name = member?.name.trim();
  return (name == null || name.isEmpty) ? deactivatedMemberName : name;
}

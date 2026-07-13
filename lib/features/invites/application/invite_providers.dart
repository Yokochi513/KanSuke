import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/firebase_providers.dart';
import '../data/invite_repository.dart';

/// 招待リンクの発行・確認・受諾・取り消し（Callable Function 経由、FR-9 / Issue #90）。
final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return FunctionsInviteRepository(functions: ref.watch(functionsProvider));
});

/// アプリを起動した URI（`kansuke://invite?token=...` / Web の `?token=...`）。
///
/// 初回起動時のリンクと、起動中に開かれたリンクの両方が流れる。テストや
/// プラグインを使えない環境ではこのプロバイダを override する。
final inviteLinkStreamProvider = StreamProvider<Uri>((ref) {
  return AppLinks().uriLinkStream;
});

/// 受諾待ちの招待トークン。リンクで起動したときに設定し、受諾/中止で null に戻す。
///
/// サインイン前にリンクを開いた場合もここに保持し、サインイン完了後に受諾画面へ
/// 進める（[InviteLinkGate]）。
final pendingInviteTokenProvider = StateProvider<String?>((ref) => null);

/// 受諾前の確認内容（カレンダー名・招待者名）。期限切れ・取り消し済み・使用済みは
/// [InviteException] として流れ、受諾画面が理由を表示する。
final invitePreviewProvider = FutureProvider.family<InvitePreview, String>((
  ref,
  token,
) {
  return ref.watch(inviteRepositoryProvider).previewInvite(token);
});

/// カレンダーの発行済み招待リンク一覧（取り消し導線用）。
///
/// `invites` はクライアントから read できないため Callable で取得する。発行・
/// 取り消しの後は `ref.invalidate` で取り直す。
final calendarInvitesProvider =
    FutureProvider.family<List<IssuedInvite>, String>((ref, calendarId) {
      return ref.watch(inviteRepositoryProvider).listInvites(calendarId);
    });

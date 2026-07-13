import 'package:kansuke/features/invites/data/invite_repository.dart';

/// 招待リンクの Callable（FR-9 / Issue #90）を模し、呼び出しを記録するフェイク。
///
/// 実装は Cloud Functions にしかないため、UI のテストではこれを差し込む。
class FakeInviteRepository implements InviteRepository {
  FakeInviteRepository({
    this.created,
    this.preview,
    this.invites = const [],
    this.acceptedCalendarId = 'shared',
    this.error,
  });

  /// `createInvite` が返す招待（省略時は既定値を組み立てる）。
  CreatedInvite? created;

  /// `previewInvite` が返す確認内容（省略時は既定値）。
  InvitePreview? preview;

  /// `listInvites` が返す発行済みリンク。
  List<IssuedInvite> invites;

  /// `acceptInvite` が返す参加先カレンダー ID。
  String acceptedCalendarId;

  /// 非 null なら全ての呼び出しがこの例外で失敗する。
  InviteException? error;

  final calls = <String>[];

  @override
  Future<CreatedInvite> createInvite(String calendarId) async {
    _record('createInvite($calendarId)');
    return created ??
        CreatedInvite(
          inviteId: 'invite-1',
          token: 'token-1',
          expiresAt: DateTime(2026, 7, 2, 9, 30),
        );
  }

  @override
  Future<InvitePreview> previewInvite(String token) async {
    _record('previewInvite($token)');
    return preview ??
        const InvitePreview(
          calendarId: 'shared',
          calendarName: 'わが家',
          invitedByName: 'ぱぱ',
          alreadyMember: false,
        );
  }

  @override
  Future<String> acceptInvite(String token) async {
    _record('acceptInvite($token)');
    return acceptedCalendarId;
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    _record('revokeInvite($inviteId)');
  }

  @override
  Future<List<IssuedInvite>> listInvites(String calendarId) async {
    _record('listInvites($calendarId)');
    return invites;
  }

  void _record(String call) {
    calls.add(call);
    final failure = error;
    if (failure != null) throw failure;
  }
}

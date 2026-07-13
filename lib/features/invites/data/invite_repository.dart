import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/logger.dart';

const _logTag = 'InviteRepository';

/// 招待リンク（FR-9 / Issue #90）。
///
/// `invites` は Security Rules でクライアントからの read/write を全面禁止して
/// いるため、発行・確認・受諾・取り消し・一覧はすべて Callable Function
/// （`functions/invites.js`）を唯一の経路とする。
abstract interface class InviteRepository {
  /// 招待リンクを発行する（カレンダーのメンバーなら誰でも）。
  Future<CreatedInvite> createInvite(String calendarId);

  /// 受諾前の確認。未参加者は `calendars` を read できないため、カレンダー名と
  /// 招待者名はこの経路でのみ得られる。
  Future<InvitePreview> previewInvite(String token);

  /// 招待を受諾してカレンダーに参加する。参加したカレンダーの ID を返す。
  Future<String> acceptInvite(String token);

  /// 招待リンクを取り消す（発行者本人またはオーナー）。
  Future<void> revokeInvite(String inviteId);

  /// カレンダーの発行済み招待リンク一覧（メンバーなら誰でも）。
  Future<List<IssuedInvite>> listInvites(String calendarId);
}

/// 発行された招待リンク。[token] は発行時にだけ得られ、以後は再表示できない
/// （Firestore にはハッシュしか保存しないため）。
class CreatedInvite {
  const CreatedInvite({
    required this.inviteId,
    required this.token,
    required this.expiresAt,
  });

  final String inviteId;
  final String token;
  final DateTime expiresAt;
}

/// 受諾前に表示する招待の内容。
class InvitePreview {
  const InvitePreview({
    required this.calendarId,
    required this.calendarName,
    required this.invitedByName,
    required this.alreadyMember,
  });

  final String calendarId;
  final String calendarName;
  final String invitedByName;

  /// 既にこのカレンダーのメンバーか（受諾は冪等に成功する）。
  final bool alreadyMember;
}

/// 発行済みの招待リンク（取り消し導線の一覧用）。トークンは含まない。
class IssuedInvite {
  const IssuedInvite({
    required this.id,
    required this.invitedBy,
    required this.expiresAt,
    required this.maxUses,
    required this.usedCount,
    required this.revoked,
    required this.active,
  });

  final String id;
  final String invitedBy;
  final DateTime expiresAt;
  final int maxUses;
  final int usedCount;
  final bool revoked;

  /// 有効期限内・未使用・未取り消しで、まだ参加に使えるか。
  final bool active;
}

/// 招待リンクが使えない理由。UI の出し分けに使う（Functions が `details.reason`
/// で返す）。
enum InviteErrorReason {
  /// トークンが存在しない（URL の書き間違い・削除済みなど）。
  notFound,

  /// 有効期限切れ。
  expired,

  /// 発行者またはオーナーが取り消した。
  revoked,

  /// 使用回数の上限に達した。
  used,

  /// 権限不足（非メンバーの発行・取り消しなど）。
  permissionDenied,

  /// 上記以外（通信エラーなど）。
  unknown,
}

/// 招待リンクの操作が失敗した理由。UI では [message] をそのまま表示する。
class InviteException implements Exception {
  const InviteException(
    this.message, {
    this.reason = InviteErrorReason.unknown,
  });

  final String message;
  final InviteErrorReason reason;

  @override
  String toString() => 'InviteException($reason): $message';
}

class FunctionsInviteRepository implements InviteRepository {
  FunctionsInviteRepository({required FirebaseFunctions functions})
    : _functions = functions;

  final FirebaseFunctions _functions;

  @override
  Future<CreatedInvite> createInvite(String calendarId) async {
    final data = await _call('createinvite', {'calendarId': calendarId});
    return CreatedInvite(
      inviteId: data['inviteId'] as String,
      token: data['token'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
    );
  }

  @override
  Future<InvitePreview> previewInvite(String token) async {
    final data = await _call('previewinvite', {'token': token});
    return InvitePreview(
      calendarId: data['calendarId'] as String,
      calendarName: data['calendarName'] as String? ?? '',
      invitedByName: data['invitedByName'] as String? ?? '',
      alreadyMember: data['alreadyMember'] as bool? ?? false,
    );
  }

  @override
  Future<String> acceptInvite(String token) async {
    final data = await _call('acceptinvite', {'token': token});
    return data['calendarId'] as String;
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    await _call('revokeinvite', {'inviteId': inviteId});
  }

  @override
  Future<List<IssuedInvite>> listInvites(String calendarId) async {
    final data = await _call('listinvites', {'calendarId': calendarId});
    final invites = data['invites'] as List<Object?>? ?? const [];
    return [
      for (final invite in invites.cast<Map<Object?, Object?>>())
        IssuedInvite(
          id: invite['id']! as String,
          invitedBy: invite['invitedBy'] as String? ?? '',
          expiresAt: DateTime.parse(invite['expiresAt']! as String).toLocal(),
          maxUses: (invite['maxUses'] as num?)?.toInt() ?? 1,
          usedCount: (invite['usedCount'] as num?)?.toInt() ?? 0,
          revoked: invite['revoked'] as bool? ?? false,
          active: invite['active'] as bool? ?? false,
        ),
    ];
  }

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> parameters,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(name)
          .call<Object?>(parameters);
      return result.data as Map<Object?, Object?>? ?? const {};
    } on FirebaseFunctionsException catch (error, stackTrace) {
      AppLogger.error(
        'Callable $name failed (${error.code})',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      // Functions の HttpsError は利用者向けの日本語メッセージを持つ
      // （「有効期限が切れています」など）ため、そのまま見せる。
      throw InviteException(
        error.message ?? '操作に失敗しました。通信環境を確認してください。',
        reason: _reasonOf(error),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Callable $name failed',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const InviteException('操作に失敗しました。通信環境を確認してください。');
    }
  }

  InviteErrorReason _reasonOf(FirebaseFunctionsException error) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch (reason) {
      'not-found' => InviteErrorReason.notFound,
      'expired' => InviteErrorReason.expired,
      'revoked' => InviteErrorReason.revoked,
      'used' => InviteErrorReason.used,
      _ => switch (error.code) {
        'not-found' => InviteErrorReason.notFound,
        'permission-denied' => InviteErrorReason.permissionDenied,
        _ => InviteErrorReason.unknown,
      },
    };
  }
}

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/logger.dart';

const _logTag = 'CalendarMembershipRepository';

/// カレンダーのメンバー管理（FR-8 / Issue #89）。
///
/// `memberIds` / `ownerId` は Security Rules でクライアントからの書き換えを禁止して
/// いるため、メンバーの削除・退出・オーナー移譲は Callable Function（`functions/
/// membership.js`）を唯一の経路とする。カレンダー自体の削除（Issue #169）も同じく
/// `allow delete` を持たないため、ここを経路にする。
abstract interface class CalendarMembershipRepository {
  /// メンバーを削除する（オーナーのみ）。
  Future<void> removeMember({required String calendarId, required String uid});

  /// 自分がカレンダーから退出する（オーナーは移譲するまで退出できない）。
  Future<void> leaveCalendar(String calendarId);

  /// オーナーを他のメンバーへ移譲する（オーナーのみ）。
  Future<void> transferOwnership({
    required String calendarId,
    required String uid,
  });

  /// カレンダーを配下の予定ごと削除する（オーナーのみ、Issue #169）。
  ///
  /// 全メンバーのカレンダーから消える。参加しているカレンダーが 1 つだけのときは
  /// Function 側で拒否される。
  Future<void> deleteCalendar(String calendarId);
}

/// 操作が拒否された理由。UI ではこのメッセージをそのまま表示する。
class CalendarMembershipException implements Exception {
  const CalendarMembershipException(this.message);

  final String message;

  @override
  String toString() => 'CalendarMembershipException: $message';
}

class FunctionsCalendarMembershipRepository
    implements CalendarMembershipRepository {
  FunctionsCalendarMembershipRepository({required FirebaseFunctions functions})
    : _functions = functions;

  final FirebaseFunctions _functions;

  @override
  Future<void> removeMember({required String calendarId, required String uid}) {
    return _call('removemember', {'calendarId': calendarId, 'targetUid': uid});
  }

  @override
  Future<void> leaveCalendar(String calendarId) {
    return _call('leavecalendar', {'calendarId': calendarId});
  }

  @override
  Future<void> transferOwnership({
    required String calendarId,
    required String uid,
  }) {
    return _call('transferownership', {
      'calendarId': calendarId,
      'targetUid': uid,
    });
  }

  @override
  Future<void> deleteCalendar(String calendarId) {
    return _call('deletecalendar', {'calendarId': calendarId});
  }

  Future<void> _call(String name, Map<String, Object?> parameters) async {
    try {
      await _functions.httpsCallable(name).call<void>(parameters);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      AppLogger.error(
        'Callable $name failed (${error.code})',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      // Functions が返す HttpsError のメッセージは利用者向けに書いてある
      // （「オーナーは退出できません」など）ため、そのまま見せる。
      throw CalendarMembershipException(
        error.message ?? '操作に失敗しました。通信環境を確認してください。',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Callable $name failed',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const CalendarMembershipException('操作に失敗しました。通信環境を確認してください。');
    }
  }
}

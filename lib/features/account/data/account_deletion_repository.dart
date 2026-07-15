import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/logger.dart';

const _logTag = 'AccountDeletionRepository';

/// アカウント削除（退会、Issue #102）。
///
/// Auth ユーザーの削除・他人のカレンダーの更新・関連データの整理は Security Rules
/// では行えないため、退会処理は Callable Function（`functions/deleteaccount.js`、
/// Admin SDK）を唯一の経路とする。削除対象は常に呼び出し元本人。
abstract interface class AccountDeletionRepository {
  /// 自分のアカウントと関連データを削除する。
  Future<void> deleteAccount();
}

/// 削除が失敗した理由。UI ではこのメッセージをそのまま表示する。
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

class FunctionsAccountDeletionRepository implements AccountDeletionRepository {
  FunctionsAccountDeletionRepository({required FirebaseFunctions functions})
    : _functions = functions;

  final FirebaseFunctions _functions;

  @override
  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteaccount').call<void>();
    } on FirebaseFunctionsException catch (error, stackTrace) {
      AppLogger.error(
        'Callable deleteaccount failed (${error.code})',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw AccountDeletionException(
        error.message ?? 'アカウントの削除に失敗しました。通信環境を確認してください。',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Callable deleteaccount failed',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const AccountDeletionException('アカウントの削除に失敗しました。通信環境を確認してください。');
    }
  }
}

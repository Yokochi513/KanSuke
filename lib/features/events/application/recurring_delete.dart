import '../data/event_repository.dart';

/// 繰り返し予定の削除範囲（#86）。この予定のみ / これ以降 / すべて。
///
/// 編集画面（#86）と日別一覧（#146）の双方から同じ削除ロジックを呼ぶため、
/// 範囲の表現と実際の書き込みをこのファイルに集約する。導線が増えても
/// 「どの範囲でどう消えるか」がずれないようにする狙い。
enum RecurringDeleteScope { thisOnly, thisAndFollowing, all }

/// 対象の発生日が繰り返しの先頭かどうか（#86 / #146）。
///
/// 先頭の発生日を「これ以降」で消すと 1 件も残らないため、削除方法と画面の
/// 文言をこの判定で切り替える。
bool isFirstRecurrenceOccurrence({
  required DateTime masterStartAt,
  required DateTime occurrenceStartAt,
}) => !occurrenceStartAt.isAfter(masterStartAt);

/// 繰り返し予定を [scope] の範囲で削除する（#86 のロジックを #146 で共有化）。
///
/// - [RecurringDeleteScope.thisOnly]: [occurrenceStartAt] を例外日（EXDATE 相当）
///   として除外する。他の回は残る。
/// - [RecurringDeleteScope.thisAndFollowing]: [occurrenceStartAt] を打ち切り日に
///   設定する。先頭の発生日なら 1 件も残らないため、すべて削除に帰着させる。
/// - [RecurringDeleteScope.all]: 元ドキュメントごとソフト削除する。
///
/// [masterStartAt] は元ドキュメントの開始日時（先頭発生日）、
/// [occurrenceStartAt] は操作対象の発生日の開始日時。展開済みの発生日
/// （`Event.occurrenceAt`）なら `recurrenceMasterStartAt` と `startAt` が
/// それぞれに対応する。
Future<void> deleteRecurringEvent(
  EventRepository repository, {
  required String eventId,
  required DateTime masterStartAt,
  required DateTime occurrenceStartAt,
  required RecurringDeleteScope scope,
  required String updatedBy,
}) {
  switch (scope) {
    case RecurringDeleteScope.thisOnly:
      return repository.excludeOccurrence(
        eventId,
        occurrenceStartAt,
        updatedBy: updatedBy,
      );
    case RecurringDeleteScope.thisAndFollowing:
      // 先頭の発生日から消すと 1 件も残らないため、すべて削除に帰着させる。
      if (isFirstRecurrenceOccurrence(
        masterStartAt: masterStartAt,
        occurrenceStartAt: occurrenceStartAt,
      )) {
        return repository.softDelete(eventId, updatedBy: updatedBy);
      }
      return repository.truncateRecurrenceFrom(
        eventId,
        occurrenceStartAt,
        updatedBy: updatedBy,
      );
    case RecurringDeleteScope.all:
      return repository.softDelete(eventId, updatedBy: updatedBy);
  }
}

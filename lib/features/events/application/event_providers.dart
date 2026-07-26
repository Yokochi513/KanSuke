import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../data/event_repository.dart';

/// 期間を表す値。`StreamProvider.family` の引数キーに用いる。
///
/// レコードの構造的等価性により、同じ期間なら同一ストリームを共有する。
typedef DateRange = ({DateTime start, DateTime end});

/// 期間＋対象カレンダーを表す値。`StreamProvider.family` の引数キーに用いる
/// （FR-8）。レコードの構造的等価性により、同じ条件なら同一ストリームを共有する。
typedef EventQuery = ({DateTime start, DateTime end, String calendarId});

/// [EventRepository]。Firestore のみに依存し、認証状態には依存しない。
///
/// 書き込みの `updatedBy` は呼び出し側が [currentUidProvider] を読んで渡す。
/// これにより購読グラフが認証に依存せず、サインアウト時のテアダウン中に
/// 購読が dirty 化してビルド中に再描画スケジュールが走るのを防ぐ。
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(firestore: ref.watch(firestoreProvider));
});

/// 指定期間・指定カレンダーの予定をリアルタイムに供給する
/// （FR-4 の月表示・日別一覧、FR-8 のカレンダー切替が購読）。
final eventsInRangeProvider = StreamProvider.family<List<Event>, EventQuery>((
  ref,
  query,
) {
  return ref
      .watch(eventRepositoryProvider)
      .watchRange(
        start: query.start,
        end: query.end,
        calendarId: query.calendarId,
      );
});

/// 指定期間・表示中カレンダー **すべて** の予定を 1 本のリストに束ねて購読する
/// （FR-4 / FR-8、Issue #170 の重ね表示）。
///
/// カレンダーごとに [eventsInRangeProvider] を購読して結果を合成する。1 本の
/// `whereIn` にまとめない理由は Security Rules にある: events の list クエリは
/// `calendarId` の **等値** where 句でしかルール適合を静的に証明できないため
/// （`firestore.rules` の `isCalendarMember()`、FR-8）、カレンダーごとに等値
/// クエリを張る形なら既存の証明可能性と複合インデックス
/// （deleted ASC, calendarId ASC, startAt ASC）をそのまま維持できる。
///
/// 合成をプロバイダではなく画面側の関数で行うのは、購読グラフの形を単一
/// カレンダーのときと同じ「widget → [eventsInRangeProvider]」に保つため。
/// あいだにプロバイダを挟むと、ストリームの更新でそのプロバイダが自己無効化し、
/// 画面遷移などで購読が再開されるビルド中に再描画がスケジュールされて
/// "setState() called during build" になる。
AsyncValue<List<Event>> watchEventsForCalendars(
  WidgetRef ref, {
  required DateTime start,
  required DateTime end,
  required List<String> calendarIds,
}) {
  if (calendarIds.isEmpty) {
    return const AsyncValue<List<Event>>.data(<Event>[]);
  }
  return mergeEventResults([
    for (final calendarId in calendarIds)
      ref.watch(
        eventsInRangeProvider((start: start, end: end, calendarId: calendarId)),
      ),
  ]);
}

/// カレンダーごとの購読結果を 1 本に合成する（Issue #170）。
///
/// - どれか 1 本でもエラーなら、そのエラーを返す（1 カレンダーの失敗を黙って
///   隠すと「予定が消えた」ように見えるため）。
/// - どの 1 本もまだ値を持たないなら loading。
/// - 1 本でも値があれば、その時点で揃っているぶんを返す（オフラインファースト。
///   ローカルキャッシュ起点で先に描き、残りは届き次第に反映する、NFR-1）。
AsyncValue<List<Event>> mergeEventResults(
  List<AsyncValue<List<Event>>> results,
) {
  if (results.isEmpty) {
    return const AsyncValue<List<Event>>.data(<Event>[]);
  }
  for (final result in results) {
    if (result.hasError) {
      return AsyncValue<List<Event>>.error(
        result.error!,
        result.stackTrace ?? StackTrace.empty,
      );
    }
  }
  if (!results.any((result) => result.hasValue)) {
    return const AsyncValue<List<Event>>.loading();
  }

  final merged = [
    for (final result in results) ...result.value ?? const <Event>[],
  ];
  // 単一カレンダーのときと同じ並び（開始→終了→id）に揃え、レーン配置や
  // 一覧の並びがカレンダーの購読順で揺れないようにする。
  merged.sort(compareEventsBySchedule);
  return AsyncValue<List<Event>>.data(List.unmodifiable(merged));
}

/// 予定を日程順（開始→終了→id）に並べる比較関数（Issue #170）。
///
/// `EventRepository.watchRange` が 1 カレンダー内で使う並びと同じ規則で、
/// 複数カレンダーを合成したリストにも決定的な順序を与える。
int compareEventsBySchedule(Event first, Event second) {
  final byStart = first.startAt.compareTo(second.startAt);
  if (byStart != 0) return byStart;
  final byEnd = first.endAt.compareTo(second.endAt);
  if (byEnd != 0) return byEnd;
  return first.id.compareTo(second.id);
}

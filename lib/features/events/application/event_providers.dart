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

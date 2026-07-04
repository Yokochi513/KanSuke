import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../data/event_repository.dart';

/// 期間を表す値。`StreamProvider.family` の引数キーに用いる。
///
/// レコードの構造的等価性により、同じ期間なら同一ストリームを共有する。
typedef DateRange = ({DateTime start, DateTime end});

/// 認証済みユーザー向けの [EventRepository]。
///
/// 未認証状態では画面に到達しない前提だが、防御的に例外を投げる。
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('未認証状態では EventRepository を利用できません。');
  }
  return EventRepository(
    firestore: ref.watch(firestoreProvider),
    currentUid: uid,
  );
});

/// 指定期間の予定をリアルタイムに供給する（FR-4 の月表示・日別一覧が購読）。
final eventsInRangeProvider = StreamProvider.family<List<Event>, DateRange>((
  ref,
  range,
) {
  return ref
      .watch(eventRepositoryProvider)
      .watchRange(start: range.start, end: range.end);
});

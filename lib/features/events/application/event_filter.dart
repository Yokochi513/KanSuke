import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../calendars/application/calendar_providers.dart';
import '../../users/application/user_providers.dart';

/// 参加者フィルタ（Issue #78、FR-2 の視覚識別を補完）。
///
/// [selectedMemberIds] が空なら全件を返す（既定＝絞り込みなし）。空でなければ、
/// 選択されたメンバーの **いずれか** が予定の参加者（[Event.memberIds]）に含まれる
/// 予定だけを返す（OR 条件）。フィルタは表示上の絞り込みのみで、データは変更しない。
///
/// 判定には [Event.participantIds] ではなく [Event.memberIds] を使う。これにより、
/// 参加者未設定の旧データ（作成者へフォールバックして表示される予定）も、月表示・
/// 日別一覧に見えている「誰の予定か」と一致して絞り込める。
List<Event> filterEventsByMembers(
  List<Event> events,
  Set<String> selectedMemberIds,
) {
  if (selectedMemberIds.isEmpty) return events;
  return [
    for (final event in events)
      if (event.memberIds.any(selectedMemberIds.contains)) event,
  ];
}

/// 月表示・日別一覧で現在有効な参加者フィルタ（選択中メンバー ID の集合、Issue #78）。
///
/// 空集合＝絞り込みなし（全件表示）。画面（月表示／日別一覧）をまたいで共有する。
/// フィルタ候補は表示中カレンダーの参加者に依存するため、表示中カレンダー集合を
/// 変えたら絞り込みをリセットする。永続化はしない（セッション内保持）。
final memberFilterProvider =
    NotifierProvider<MemberFilterNotifier, Set<String>>(
      MemberFilterNotifier.new,
    );

class MemberFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // カレンダー切替でフィルタをリセットする（参加者一覧が変わるため）。
    //
    // 表示中カレンダー（[visibleCalendarIdsProvider]）は、ユーザーの切替操作だけで
    // なくカレンダー一覧の読み込み完了やサインアウトでも変わり、それは widget の
    // build 中に起こりうる。build 中に状態を書き替えると "setState() called during
    // build" になるため、依存（watch）にはせず listen で受け、リセットは次の
    // マイクロタスク（build フェーズの外）で行う。
    var disposed = false;
    ref.onDispose(() => disposed = true);
    ref.listen(visibleCalendarIdsProvider, (previous, next) {
      // Issue #170: 集合は毎回別インスタンスになりうるので中身で比較する。
      if (previous != null && _sameIds(previous, next)) return;
      scheduleMicrotask(() {
        if (disposed) return;
        state = const {};
      });
    });
    return const {};
  }

  /// メンバーの選択/解除を切り替える。
  void toggle(String memberId) {
    final next = {...state};
    if (!next.remove(memberId)) {
      next.add(memberId);
    }
    state = next;
  }

  /// 絞り込みを解除して全件表示に戻す。
  void clear() => state = const {};
}

bool _sameIds(List<String> first, List<String> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

/// フィルタ候補となる参加者一覧（表示中カレンダーの参加者、Issue #78）。
///
/// Issue #170: 重ね表示では表示中カレンダー **すべて** の `memberIds` の和集合を
/// 候補にする。候補が表示中の予定に現れうる人と一致していないと、絞り込んだ結果
/// 何も出ない／絞り込めない人が出るため。表示順で先に出るカレンダーの参加者から
/// 並べ、重複は除く。カレンダーが読み込み中などで見つからない場合は、全家族
/// メンバーを候補にする。
final filterableMembersProvider = Provider<List<User>>((ref) {
  // 表示中カレンダーは [visibleCalendarsProvider] を watch せず、ヘルパで元データ
  // から組み立てる。プロバイダ同士を連ねるとビルド中の再スケジュールを招くため
  // （[watchVisibleCalendars] のコメント）。
  final visibleCalendars = watchVisibleCalendars(ref);
  final membersById = ref.watch(membersByIdProvider);

  final seen = <String>{};
  final memberIds = [
    for (final calendar in visibleCalendars)
      for (final memberId in calendar.memberIds)
        if (seen.add(memberId)) memberId,
  ];
  if (memberIds.isEmpty) {
    return ref.watch(familyMembersProvider).asData?.value ?? const <User>[];
  }
  return [
    for (final id in memberIds)
      if (membersById[id] != null) membersById[id]!,
  ];
});

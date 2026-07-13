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
/// フィルタ候補は表示中カレンダーの参加者に依存するため、カレンダーを切り替えたら
/// 絞り込みをリセットする。永続化はしない（セッション内保持）。
final memberFilterProvider =
    NotifierProvider<MemberFilterNotifier, Set<String>>(
      MemberFilterNotifier.new,
    );

class MemberFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // カレンダー切替でフィルタをリセットする（参加者一覧が変わるため）。
    //
    // 表示中カレンダー（[selectedCalendarIdProvider]）は、ユーザーの切替操作だけで
    // なくカレンダー一覧の読み込み完了やサインアウトでも変わり、それは widget の
    // build 中に起こりうる。build 中に状態を書き替えると "setState() called during
    // build" になるため、依存（watch）にはせず listen で受け、リセットは次の
    // マイクロタスク（build フェーズの外）で行う。
    var disposed = false;
    ref.onDispose(() => disposed = true);
    ref.listen(selectedCalendarIdProvider, (previous, next) {
      if (previous == next) return;
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

/// フィルタ候補となる参加者一覧（表示中カレンダーの参加者、Issue #78）。
///
/// 表示中カレンダーの `memberIds` を家族メンバー情報（色・名前）に解決して返す。
/// カレンダーが読み込み中などで見つからない場合は、全家族メンバーを候補にする。
final filterableMembersProvider = Provider<List<User>>((ref) {
  final calendarId = ref.watch(selectedCalendarIdProvider);
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final membersById = ref.watch(membersByIdProvider);

  final calendar = calendars.cast<Calendar?>().firstWhere(
    (c) => c?.id == calendarId,
    orElse: () => null,
  );
  final memberIds = calendar?.memberIds ?? const <String>[];
  if (memberIds.isEmpty) {
    return ref.watch(familyMembersProvider).asData?.value ?? const <User>[];
  }
  return [
    for (final id in memberIds)
      if (membersById[id] != null) membersById[id]!,
  ];
});

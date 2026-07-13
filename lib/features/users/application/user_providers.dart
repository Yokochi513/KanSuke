import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
import '../data/user_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(firestore: ref.watch(firestoreProvider));
});

/// サインイン中の自分のユーザードキュメント（FR-2 の識別色など）。
final currentUserProvider = StreamProvider<User?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(null);
  }
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

/// 自分に見えてよいメンバーの uid（自分＋参加カレンダーの参加者、Issue #89）。
///
/// `users` は列挙禁止（`firestore.rules`）のため、メンバー情報はここで得た uid を
/// 個別に get して集める。区切り文字で連結した1つの文字列にするのは、uid 集合が
/// 実際に変わったときだけ [familyMembersProvider] の購読を張り直すため
/// （List/Set は等価比較が同一性になり、カレンダーが更新されるたびに再購読になる）。
final visibleMemberIdsProvider = Provider<String>((ref) {
  final uid = ref.watch(currentUidProvider);
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final ids = <String>{
    ?uid,
    for (final calendar in calendars) ...calendar.memberIds,
  };
  return (ids.toList()..sort()).join(',');
});

/// 家族メンバー一覧（FR-2 の色・名前）。予定表示のマスタとして購読する。
///
/// 対象の uid（[visibleMemberIdsProvider]）は参加カレンダーの増減で変わる。`watch`
/// せず `listen` で受けて購読先だけを差し替えるのは、uid が変わるたびにこの
/// プロバイダ自身が再構築されると、ビルド中の再構築要求になり得るため。
final familyMembersProvider = StreamProvider<List<User>>((ref) {
  final repository = ref.watch(userRepositoryProvider);
  final controller = StreamController<List<User>>();
  StreamSubscription<List<User>>? subscription;

  void subscribe(String ids) {
    subscription?.cancel();
    subscription = repository
        .watchUsers(ids.isEmpty ? const [] : ids.split(','))
        .listen(controller.add, onError: controller.addError);
  }

  ref.listen(visibleMemberIdsProvider, (_, ids) => subscribe(ids));
  subscribe(ref.read(visibleMemberIdsProvider));

  ref.onDispose(() {
    subscription?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// uid をキーにメンバーを引ける Map。予定の参加者色を引くのに使う。
final membersByIdProvider = Provider<Map<String, User>>((ref) {
  final members = ref.watch(familyMembersProvider).asData?.value ?? const [];
  return {for (final member in members) member.id: member};
});

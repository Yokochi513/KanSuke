import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../data/user_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(firestore: ref.watch(firestoreProvider));
});

/// 家族メンバー一覧（FR-2 の色・名前）。予定表示のマスタとして購読する。
final familyMembersProvider = StreamProvider<List<User>>((ref) {
  return ref.watch(userRepositoryProvider).watchMembers();
});

/// uid をキーにメンバーを引ける Map。予定の所有者色を引くのに使う。
final membersByIdProvider = Provider<Map<String, User>>((ref) {
  final members = ref.watch(familyMembersProvider).asData?.value ?? const [];
  return {for (final member in members) member.id: member};
});

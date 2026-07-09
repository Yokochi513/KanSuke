import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../data/calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(firestore: ref.watch(firestoreProvider));
});

/// 自分が参加しているカレンダー一覧（FR-8）。カレンダー切替・予定編集の
/// カレンダー選択・参加者候補の絞り込みに用いる。
final myCalendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return Stream.value(const []);
  }
  return ref.watch(calendarRepositoryProvider).watchMine(uid);
});

/// 月表示・日別一覧で現在選択中のカレンダー ID（FR-8）。
///
/// 既定表示は既定カレンダー（わが家）。画面をまたいで選択状態を共有する。
final selectedCalendarIdProvider = StateProvider<String>(
  (ref) => defaultCalendarId,
);

/// サインイン確定後に既定カレンダーの存在を保証する（FR-8）。
///
/// UI をブロックしない副作用としてアプリ起動時に一度 watch する想定。
/// Firestore への反映は各種ストリームプロバイダ経由でリアクティブに届く。
final calendarBootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;
  final members = await ref.watch(familyMembersProvider.future);
  await ref
      .watch(calendarRepositoryProvider)
      .ensureDefaultCalendar(
        uid: uid,
        knownMemberIds: [for (final member in members) member.id],
      );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
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

/// ユーザーがカレンダー切替で明示的に選んだカレンダー ID（未選択なら null）。
///
/// 表示に使う ID は [selectedCalendarIdProvider] で解決する。切替 UI 以外から
/// このプロバイダを直接読まないこと。
final calendarSelectionProvider = StateProvider<String?>((ref) => null);

/// 月表示・日別一覧で現在表示しているカレンダー ID（FR-8）。画面をまたいで共有する。
///
/// 明示的な選択（[calendarSelectionProvider]）が自分の参加カレンダーに無い場合
/// （未選択、退出済み、別端末で選んだカレンダーなど）は、一覧の先頭を表示する。
/// アカウント作成時に個人カレンダーが必ず 1 つ作られるため、一覧が空になるのは
/// 初回同期を待っている間だけで、その間は空文字（＝該当予定なし）を返す。
final selectedCalendarIdProvider = Provider<String>((ref) {
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final selectedId = ref.watch(calendarSelectionProvider);
  if (calendars.any((calendar) => calendar.id == selectedId)) {
    return selectedId!;
  }
  return calendars.isEmpty ? '' : calendars.first.id;
});

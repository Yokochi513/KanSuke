import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/models.dart';
import '../../auth/application/auth_state.dart';
import '../data/calendar_membership_repository.dart';
import '../data/calendar_repository.dart';
import 'calendar_order.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(firestore: ref.watch(firestoreProvider));
});

/// メンバーの削除・退出・オーナー移譲（Callable Function 経由、Issue #89）。
final calendarMembershipRepositoryProvider =
    Provider<CalendarMembershipRepository>((ref) {
      return FunctionsCalendarMembershipRepository(
        functions: ref.watch(functionsProvider),
      );
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

const _calendarOrderKey = 'calendars.order';

/// ユーザーが手動で並べ替えたカレンダー ID の順序（未設定なら空、Issue #168）。
///
/// 並び順は個人の好みなので端末ローカル（[SharedPreferences]）に持ち、Firestore の
/// クエリ（名前昇順）はそのまま残してクライアント側で並べ替える。家族の他メンバーや
/// 他端末の表示には影響しない。
///
/// 表示用の並び替え済み一覧は [orderedCalendarsProvider] を使うこと。
final calendarOrderProvider =
    AsyncNotifierProvider<CalendarOrderController, List<String>>(
      CalendarOrderController.new,
    );

class CalendarOrderController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_calendarOrderKey) ?? const <String>[];
  }

  /// 並べ替えた結果を保存する。
  Future<void> save(List<String> calendarIds) async {
    // 保存の完了を待たずに画面へ反映し、ドラッグ結果を即座に見せる。
    state = AsyncData(List.unmodifiable(calendarIds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_calendarOrderKey, calendarIds);
  }
}

/// 手動の並び順を反映した、自分が参加しているカレンダー一覧（FR-8 / Issue #168）。
///
/// カレンダー管理画面と切替 UI はこちらを使う。順序の読み込み中・失敗時は保存前と
/// 同じ名前昇順（Firestore のクエリ順）になる。
final orderedCalendarsProvider = Provider<List<Calendar>>((ref) {
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final order = ref.watch(calendarOrderProvider).value ?? const <String>[];
  return sortCalendarsByOrder(calendars, order);
});

const _selectedCalendarIdKey = 'calendars.selected_id';

/// ユーザーがカレンダー切替で明示的に選んだカレンダー ID（未選択なら null）。
///
/// 端末ローカル（[SharedPreferences]）に保存し、起動時に前回開いていたカレンダーを
/// 復元する（Issue #167）。どのカレンダーを開いているかは端末ごとの都合なので、
/// テーマ設定と同じく Firestore ではなくローカルに持ち、家族の他メンバーや他端末に
/// 影響させない。
///
/// 表示に使う ID は [selectedCalendarIdProvider] で解決する。切替 UI 以外から
/// このプロバイダを直接読まないこと。
final calendarSelectionProvider =
    AsyncNotifierProvider<CalendarSelectionController, String?>(
      CalendarSelectionController.new,
    );

class CalendarSelectionController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedCalendarIdKey);
  }

  /// 表示するカレンダーを切り替えて保存する。
  Future<void> select(String calendarId) async {
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(calendarId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedCalendarIdKey, calendarId);
  }
}

/// 月表示・日別一覧で現在表示しているカレンダー ID（FR-8）。画面をまたいで共有する。
///
/// 明示的な選択（[calendarSelectionProvider]）が自分の参加カレンダーに無い場合
/// （未選択、退出済み、別端末で選んだカレンダーなど）は、一覧の先頭を表示する。
/// アカウント作成時に個人カレンダーが必ず 1 つ作られるため、一覧が空になるのは
/// 初回同期を待っている間だけで、その間は空文字（＝該当予定なし）を返す。
///
/// 保存済みの選択を読み込み終えるまでも同じく空文字を返す（Issue #167）。先に一覧の
/// 先頭を返してしまうと、読み込み完了時に別のカレンダーへ切り替わってちらつくため。
/// 読み込みに失敗した場合は値を持たないまま先頭へフォールバックする。
final selectedCalendarIdProvider = Provider<String>((ref) {
  final selection = ref.watch(calendarSelectionProvider);
  if (selection.isLoading && !selection.hasValue) {
    return '';
  }
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final selectedId = selection.value;
  if (calendars.any((calendar) => calendar.id == selectedId)) {
    return selectedId!;
  }
  return calendars.isEmpty ? '' : calendars.first.id;
});

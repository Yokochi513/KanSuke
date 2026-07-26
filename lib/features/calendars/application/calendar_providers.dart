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
final orderedCalendarsProvider = Provider<List<Calendar>>(
  _watchOrderedCalendars,
);

/// 並び順を反映したカレンダー一覧を、その場で組み立てる。
///
/// [orderedCalendarsProvider] を **プロバイダから** `watch` しないためのヘルパ。
/// このプロバイダは毎回新しい `List` を返し、`List` は構造的等価性を持たないので
/// 中身が同じでも「変化した」と判定されて購読側を必ず無効化する。購読側が
/// プロバイダだと、画面遷移などで購読が再開されるビルド中に自己無効化が起きて
/// "setState() called during build" になる。widget から `watch` するぶんには
/// 問題ないので、プロバイダ側はこのヘルパで元データから直接組み立てる。
List<Calendar> _watchOrderedCalendars(Ref ref) {
  final calendars =
      ref.watch(myCalendarsProvider).asData?.value ?? const <Calendar>[];
  final order = ref.watch(calendarOrderProvider).value ?? const <String>[];
  return sortCalendarsByOrder(calendars, order);
}

/// Issue #167 で導入した単一 ID の保存キー。Issue #170 で集合
/// （[_visibleCalendarIdsKey]）へ移行したが、移行元として読み続け、書き込み時も
/// 先頭カレンダーで更新し続ける（旧バージョンへ戻しても表示が壊れないように）。
const _selectedCalendarIdKey = 'calendars.selected_id';

/// 同時表示するカレンダー ID 集合の保存キー（Issue #170）。
const _visibleCalendarIdsKey = 'calendars.visible_ids';

/// 月表示・日別一覧に同時に重ねて表示できるカレンダー数の上限（Issue #170）。
///
/// 表示中カレンダーごとに Firestore のリスナを 1 本張る実装のため、上限は購読数と
/// マスの表示密度（1 マスに入る帯の本数）で決めている。家庭内運用のカレンダー数
/// （個人＋わが家＋用途別で数個）に対して十分で、将来 `whereIn` 1 本にまとめる
/// 実装へ切り替えても、その上限（30）を下回るので制約が増えない。
const int kMaxVisibleCalendars = 5;

/// ユーザーがカレンダー切替で明示的に選んだカレンダー ID の集合（未選択なら空）。
///
/// 端末ローカル（[SharedPreferences]）に保存し、起動時に前回表示していたカレンダー
/// を復元する（Issue #167、Issue #170 で集合へ拡張）。どのカレンダーを開いているか
/// は端末ごとの都合なので、テーマ設定と同じく Firestore ではなくローカルに持ち、
/// 家族の他メンバーや他端末に影響させない。
///
/// 表示に使う ID は [visibleCalendarIdsProvider] で解決する。切替 UI 以外から
/// このプロバイダを直接読まないこと。
final calendarSelectionProvider =
    AsyncNotifierProvider<CalendarSelectionController, List<String>>(
      CalendarSelectionController.new,
    );

class CalendarSelectionController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final visible = prefs.getStringList(_visibleCalendarIdsKey);
    if (visible != null) {
      return List.unmodifiable(visible);
    }
    // Issue #170: 単一 ID で保存していた頃（Issue #167）の値から移行する。
    final legacy = prefs.getString(_selectedCalendarIdKey);
    return legacy == null || legacy.isEmpty
        ? const <String>[]
        : List.unmodifiable([legacy]);
  }

  /// 表示するカレンダーを 1 つだけに切り替えて保存する。
  Future<void> select(String calendarId) => setVisible([calendarId]);

  /// 表示するカレンダー集合を差し替えて保存する（Issue #170）。
  ///
  /// 重複と空 ID を除き、[kMaxVisibleCalendars] 件で打ち切る。渡された順序を
  /// そのまま保存するが、表示順の解決は [visibleCalendarIdsProvider] が行う。
  Future<void> setVisible(List<String> calendarIds) async {
    final next = <String>[];
    for (final id in calendarIds) {
      if (id.isEmpty || next.contains(id)) continue;
      next.add(id);
      if (next.length >= kMaxVisibleCalendars) break;
    }
    // 保存の完了を待たずに画面へ反映し、切り替えを即座に見せる。
    state = AsyncData(List.unmodifiable(next));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_visibleCalendarIdsKey, next);
    // 旧キーも先頭カレンダーで更新し続ける（上のコメント参照）。
    if (next.isEmpty) {
      await prefs.remove(_selectedCalendarIdKey);
    } else {
      await prefs.setString(_selectedCalendarIdKey, next.first);
    }
  }
}

/// カレンダーの表示 ON/OFF を切り替えた結果の ID 集合を返す（Issue #170）。
///
/// 保存済みの値ではなく **解決済みの表示中集合**（[visibleCalendarIdsProvider]）
/// を渡すこと。未選択でも先頭 1 件が表示される（フォールバック）ため、保存値を
/// 起点にすると、フォールバックで表示中のカレンダーが別のカレンダーを追加した
/// 拍子に黙って消えてしまう。
///
/// 最後の 1 件は外せない（すべて非表示にすると何も見えなくなるため）。上限
/// [kMaxVisibleCalendars] に達している状態での追加も無視する。切替 UI は
/// [canAddVisibleCalendar] で先に判定してチェックボックスを無効化し、超過を防ぐ。
List<String> toggledVisibleCalendarIds(
  List<String> visibleIds,
  String calendarId,
) {
  if (visibleIds.contains(calendarId)) {
    if (visibleIds.length <= 1) return visibleIds;
    return [
      for (final id in visibleIds)
        if (id != calendarId) id,
    ];
  }
  if (!canAddVisibleCalendar(visibleIds)) return visibleIds;
  return [...visibleIds, calendarId];
}

/// 月表示・日別一覧で現在表示しているカレンダー ID（FR-8 / Issue #170）。
/// 画面をまたいで共有し、表示順（Issue #168）に整列して返す。
/// 解決の詳細は [watchVisibleCalendars] を参照。
final visibleCalendarIdsProvider = Provider<List<String>>((ref) {
  return List.unmodifiable([
    for (final calendar in watchVisibleCalendars(ref)) calendar.id,
  ]);
});

/// 表示中カレンダーの実体（表示順、Issue #170）。名前ラベルの解決に用いる。
final visibleCalendarsProvider = Provider<List<Calendar>>(
  watchVisibleCalendars,
);

/// 表示中カレンダー（表示順・参加チェック済み）をその場で組み立てる。
///
/// [visibleCalendarsProvider] / [visibleCalendarIdsProvider] /
/// [selectedCalendarIdProvider] は、いずれもこのヘルパで **元データから直接**
/// 組み立てる。プロバイダ同士を連ねないのは Riverpod の再計算の伝わり方による:
/// リストを返すプロバイダは `List` に構造的等価性が無いため中身が同じでも
/// 「変化した」と判定されて購読側を必ず無効化し、購読側がプロバイダだと自己
/// 無効化 → 再描画のスケジュールが走る。画面遷移で購読が再開される（paused →
/// resume）タイミングはビルド中なので、そこで走ると "setState() called during
/// build" になる。widget から `watch` するぶんには問題ないので、依存は
/// 「widget → プロバイダ → 元データ（Stream/Notifier）」の 1 段に保つ。
///
/// 明示的な選択（[calendarSelectionProvider]）のうち、自分の参加カレンダーに無い
/// ものは落とす（退出済み、別端末で選んだカレンダー、削除済みなど）。結果が空に
/// なる場合は表示順の先頭 1 件を表示する。アカウント作成時に個人カレンダーが必ず
/// 1 つ作られるため、一覧が空になるのは初回同期を待っている間だけ。
///
/// 保存済みの選択を読み込み終えるまでは空リストを返す（Issue #167）。先に一覧の
/// 先頭を返してしまうと、読み込み完了時に別のカレンダーへ切り替わってちらつく
/// ため。読み込みに失敗した場合は値を持たないまま先頭へフォールバックする。
List<Calendar> watchVisibleCalendars(Ref ref) {
  final selection = ref.watch(calendarSelectionProvider);
  if (selection.isLoading && !selection.hasValue) {
    return const <Calendar>[];
  }
  final calendars = _watchOrderedCalendars(ref);
  if (calendars.isEmpty) {
    return const <Calendar>[];
  }
  final saved = (selection.value ?? const <String>[]).toSet();
  final visible = [
    for (final calendar in calendars)
      if (saved.contains(calendar.id)) calendar,
  ];
  if (visible.isEmpty) {
    return [calendars.first];
  }
  return visible.take(kMaxVisibleCalendars).toList();
}

/// これ以上カレンダーを追加表示できるか（Issue #170、上限 [kMaxVisibleCalendars]）。
bool canAddVisibleCalendar(List<String> visibleIds) =>
    visibleIds.length < kMaxVisibleCalendars;

/// 予定を新規作成するときの既定カレンダー ID（FR-8 / Issue #170）。
///
/// 表示中カレンダー集合の先頭（＝表示順の先頭）を既定にする。表示していない
/// カレンダーへ予定を入れたい場合は、予定編集画面のカレンダー選択で変更できる。
/// 表示できるカレンダーがまだ無い間は空文字を返す。
final selectedCalendarIdProvider = Provider<String>((ref) {
  final visible = watchVisibleCalendars(ref);
  return visible.isEmpty ? '' : visible.first.id;
});

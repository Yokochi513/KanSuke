import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_state.dart';
import '../../calendars/application/calendar_providers.dart';
import '../../events/application/event_providers.dart';
import '../../users/application/user_providers.dart';
import '../application/home_widget_payload.dart';
import '../data/home_widget_client.dart';

/// ホーム画面ウィジェットへ予定を書き出し続ける中継（Issue #127）。
///
/// アプリ本体を包んで常時マウントし、表示中カレンダー（FR-8）の今日から
/// [homeWidgetDayCount] 日分の予定を購読して、内容が変わるたびにウィジェットへ
/// 渡す。ウィジェット側は渡された数日分から「今日・明日」を描画時に選ぶため、
/// アプリを開かない日が続いても日付の繰り上がりに追従する。
///
/// 購読を widget 側に置いているのは、既存の購読グラフの形（widget → プロバイダ
/// → 元データ）に合わせるため。プロバイダ同士を連ねると、リストを返すプロバイダ
/// の自己無効化がビルド中の再描画スケジュールを招く（`watchVisibleCalendars`
/// のコメント参照）。
class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  /// 直近に書き込みへ回したペイロード。同じ内容を繰り返し書かないため。
  String? _pushed;

  /// 書き込み待ちのペイロード（最新の 1 件だけを持つ）。
  String? _pending;

  /// 書き込み中フラグ。プラットフォームチャネルの往復より再描画が速いときに、
  /// 書き込みが積み上がらないようにする。
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    final payload = _buildPayload();
    if (payload != null && payload != _pushed && payload != _pending) {
      _pending = payload;
      // 書き込みはビルドの外へ出す（ビルド中にプロバイダを read しない）。
      WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    }
    return widget.child;
  }

  /// 現在の状態から書き込むべきペイロードを組み立てる。
  ///
  /// 予定をまだ 1 件も読めていない間は null を返し、前回の内容を残す
  /// （起動直後に一瞬「予定なし」になるのを避ける。オフラインファースト、NFR-1）。
  String? _buildPayload() {
    final currentUid = ref.watch(currentUidProvider);
    if (currentUid == null) {
      // NFR-4: サインアウトしたら、ホーム画面に家族の予定を残さない。
      return encodeHomeWidgetPayload(buildSignedOutHomeWidgetPayload());
    }

    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final end = DateTime(
      today.year,
      today.month,
      today.day + homeWidgetDayCount,
    );
    final visibleCalendars = ref.watch(visibleCalendarsProvider);
    final events = watchEventsForCalendars(
      ref,
      start: today,
      end: end,
      calendarIds: [for (final calendar in visibleCalendars) calendar.id],
    );
    final loaded = events.asData?.value;
    if (loaded == null) return null;

    return encodeHomeWidgetPayload(
      buildHomeWidgetPayload(
        events: loaded,
        membersById: ref.watch(membersByIdProvider),
        now: now,
        currentUid: currentUid,
      ),
    );
  }

  /// 待ち行列を順に書き込む。失敗しても再試行しない（付随的な更新のため、
  /// 次に内容が変わったときに書き直る）。
  Future<void> _drain() async {
    if (_pushing) return;
    _pushing = true;
    try {
      while (mounted) {
        final next = _pending;
        if (next == null) break;
        _pending = null;
        _pushed = next;
        await ref.read(homeWidgetClientProvider).push(next);
      }
    } finally {
      _pushing = false;
    }
  }
}

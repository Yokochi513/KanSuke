import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/calendars/application/calendar_providers.dart';
import '../features/calendars/presentation/calendar_edit_screen.dart';
import '../features/calendars/presentation/calendar_management_screen.dart';
import '../features/events/presentation/day_events_screen.dart';
import '../features/events/presentation/event_edit_screen.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/invites/presentation/invite_accept_screen.dart';
import '../features/invites/presentation/invite_link_gate.dart';
import '../features/settings/application/merged_bar_color_provider.dart';
import '../features/settings/application/theme_mode_provider.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/version_check/presentation/release_history_screen.dart';
import '../features/version_check/presentation/version_check_gate.dart';
import 'navigator_key.dart';
import 'routes.dart';
import 'theme.dart';
import 'washi_background.dart';

class KanSukeApp extends ConsumerWidget {
  const KanSukeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    // FR-8: カレンダー一覧（＝表示中カレンダーの解決元）を、常に生きているアプリ直下で
    // 購読し続ける。画面側の購読だけだと画面遷移中に購読が止まり、再開時に値がまとめて
    // 流れ込んで build 中の再計算になってしまう。値はここでは使わない。
    ref.listen(myCalendarsProvider, (_, _) {});

    return MaterialApp(
      title: 'KanSuke',
      debugShowCheckedModeBanner: false,
      // FR-9: 招待リンクでの起動は画面の外から遷移を起こすため（Issue #90）。
      navigatorKey: ref.watch(navigatorKeyProvider),
      // まとめ帯の地色は設定で差し替えられる（null ならテーマ既定、Issue #112）。
      theme: buildKanSukeTheme(
        mergedBarColor: ref.watch(resolvedMergedBarColorProvider),
      ),
      darkTheme: buildKanSukeDarkTheme(
        mergedBarColor: ref.watch(resolvedMergedBarColorProvider),
      ),
      // 設定画面での選択に従う（未設定なら端末のダークモード設定に追従）。
      themeMode: ref.watch(resolvedThemeModeProvider),
      // 和紙の地は Navigator の背後にも敷いておく。ページ遷移中はズームで一時的に
      // 画面が縮み、その外周のわずかな隙間に背後が覗くため、そこも和紙で埋める。
      // 招待リンク（FR-9）の受け口も Navigator の外側に置き、どの画面を開いていても
      // リンクを受けられるようにする。
      builder: (context, child) => WashiBackground(
        child: InviteLinkGate(child: child ?? const SizedBox.shrink()),
      ),
      // NFR-1: 日付ピッカー等の標準UIが英語表記になる不具合を解消する（Issue #58）。
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja')],
      locale: const Locale('ja'),
      home: _withWashi(
        authState.when(
          loading: () => const _AuthLoadingScreen(),
          error: (_, _) => const SignInScreen(
            initialErrorMessage: '認証状態を確認できませんでした。もう一度お試しください。',
          ),
          data: (session) {
            if (session != null) {
              // FR-5: 通知権限リクエストと FCM トークン登録。画面はブロックしない。
              ref.watch(notificationBootstrapProvider);
            }
            return session == null
                ? const SignInScreen()
                : const VersionCheckGate(child: CalendarScreen());
          },
        ),
      ),
      routes: {
        AppRoutes.calendar: (_) => _withWashi(const CalendarScreen()),
        AppRoutes.dayEvents: (_) => _withWashi(const DayEventsScreen()),
        AppRoutes.eventEdit: (_) => _withWashi(const EventEditScreen()),
        AppRoutes.settings: (_) => _withWashi(const SettingsScreen()),
        AppRoutes.calendarManagement: (_) =>
            _withWashi(const CalendarManagementScreen()),
        AppRoutes.calendarEdit: (_) => _withWashi(const CalendarEditScreen()),
        AppRoutes.inviteAccept: (_) => _withWashi(const InviteAcceptScreen()),
        AppRoutes.releaseHistory: (_) =>
            _withWashi(const ReleaseHistoryScreen()),
      },
    );
  }
}

/// 各画面（ルート）を不透明な和紙背景で包む（Issue #124）。
///
/// Scaffold の地は和紙テクスチャを透かすため透過（[ThemeData.scaffoldBackgroundColor]
/// が透明）にしている。しかし画面ごとに背景を持たせずに Navigator の背後へ一度だけ
/// 和紙を敷くと、戻る操作（Android の戻るジェスチャ＝画面端の左スワイプを含む）の
/// ページ遷移中に、遷移元と遷移先の透過した画面が同じ背景の上で重なって見え、画面が
/// 崩れて見えてしまう。各ルートを不透明な和紙背景（[WashiBackground] の [ColoredBox]）
/// で包むことで、遷移中は手前の画面が背後の画面をきちんと覆い隠すようにする。
///
/// 和紙の模様は固定シードで描くため、どの画面でも同じ地紋になり、静止時の見た目は
/// 背後に一度だけ敷いていたときと変わらない。
Widget _withWashi(Widget child) => WashiBackground(child: child);

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

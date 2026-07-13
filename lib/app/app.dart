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
import '../features/invites/presentation/invite_accept_screen.dart';
import '../features/invites/presentation/invite_link_gate.dart';
import '../features/settings/application/theme_mode_provider.dart';
import '../features/settings/presentation/settings_screen.dart';
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
      theme: buildKanSukeTheme(),
      darkTheme: buildKanSukeDarkTheme(),
      // 設定画面での選択に従う（未設定なら端末のダークモード設定に追従）。
      themeMode: ref.watch(resolvedThemeModeProvider),
      // 和紙の地は全画面共通の背景として Navigator の背後に一度だけ敷く。
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
      home: authState.when(
        loading: () => const _AuthLoadingScreen(),
        error: (_, _) => const SignInScreen(
          initialErrorMessage: '認証状態を確認できませんでした。もう一度お試しください。',
        ),
        data: (session) => session == null
            ? const SignInScreen()
            : const VersionCheckGate(child: CalendarScreen()),
      ),
      routes: {
        AppRoutes.calendar: (_) => const CalendarScreen(),
        AppRoutes.dayEvents: (_) => const DayEventsScreen(),
        AppRoutes.eventEdit: (_) => const EventEditScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
        AppRoutes.calendarManagement: (_) => const CalendarManagementScreen(),
        AppRoutes.calendarEdit: (_) => const CalendarEditScreen(),
        AppRoutes.inviteAccept: (_) => const InviteAcceptScreen(),
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

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
import '../features/settings/presentation/settings_screen.dart';
import '../features/version_check/presentation/version_check_gate.dart';
import 'routes.dart';
import 'theme.dart';

class KanSukeApp extends ConsumerWidget {
  const KanSukeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'KanSuke',
      debugShowCheckedModeBanner: false,
      theme: buildKanSukeTheme(),
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
        data: (session) {
          if (session != null) {
            // FR-8: 既定カレンダーの存在を保証する副作用。画面はブロックしない。
            ref.watch(calendarBootstrapProvider);
          }
          return session == null
              ? const SignInScreen()
              : const VersionCheckGate(child: CalendarScreen());
        },
      ),
      routes: {
        AppRoutes.calendar: (_) => const CalendarScreen(),
        AppRoutes.dayEvents: (_) => const DayEventsScreen(),
        AppRoutes.eventEdit: (_) => const EventEditScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
        AppRoutes.calendarManagement: (_) => const CalendarManagementScreen(),
        AppRoutes.calendarEdit: (_) => const CalendarEditScreen(),
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

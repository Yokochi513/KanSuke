import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/events/presentation/day_events_screen.dart';
import '../features/events/presentation/event_edit_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'routes.dart';
import 'theme.dart';

class KanSukeApp extends ConsumerWidget {
  const KanSukeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'KanSuke',
      debugShowCheckedModeBanner: false,
      theme: buildKanSukeTheme(),
      home: switch (authStatus) {
        AuthStatus.signedOut => const SignInScreen(),
        AuthStatus.signedIn => const CalendarScreen(),
      },
      routes: {
        AppRoutes.calendar: (_) => const CalendarScreen(),
        AppRoutes.dayEvents: (_) => const DayEventsScreen(),
        AppRoutes.eventEdit: (_) => const EventEditScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
      },
    );
  }
}

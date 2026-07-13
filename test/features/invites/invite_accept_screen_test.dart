import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/invites/application/invite_providers.dart';
import 'package:kansuke/features/invites/data/invite_repository.dart';
import 'package:kansuke/features/invites/presentation/invite_accept_screen.dart';

import 'fake_invite_repository.dart';

Future<ProviderContainer> _openAccept(
  WidgetTester tester,
  FakeInviteRepository invites, {
  String? token = 'token-1',
}) async {
  final container = ProviderContainer(
    overrides: [inviteRepositoryProvider.overrideWithValue(invites)],
  );
  addTearDown(container.dispose);
  container.read(pendingInviteTokenProvider.notifier).state = token;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InviteAcceptScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('受諾前にカレンダー名と招待者名を表示する（FR-9 / Issue #90）', (tester) async {
    final invites = FakeInviteRepository();

    await _openAccept(tester, invites);

    expect(invites.calls, ['previewInvite(token-1)']);
    expect(find.text('わが家'), findsOneWidget);
    expect(find.text('ぱぱ さんから招待されています'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '参加する'), findsOneWidget);
  });

  testWidgets('参加すると受諾し、そのカレンダーを表示対象にする', (tester) async {
    final invites = FakeInviteRepository(acceptedCalendarId: 'shared');
    final container = await _openAccept(tester, invites);

    await tester.tap(find.widgetWithText(FilledButton, '参加する'));
    await tester.pumpAndSettle();

    expect(invites.calls, ['previewInvite(token-1)', 'acceptInvite(token-1)']);
    expect(container.read(calendarSelectionProvider), 'shared');
    // 受諾待ちは解除され、同じリンクで再び開かれない。
    expect(container.read(pendingInviteTokenProvider), isNull);
    expect(find.text('「わが家」に参加しました'), findsOneWidget);
  });

  testWidgets('既にメンバーなら「カレンダーを開く」になり、受諾は冪等に成功する', (tester) async {
    final invites = FakeInviteRepository(
      preview: const InvitePreview(
        calendarId: 'shared',
        calendarName: 'わが家',
        invitedByName: 'ぱぱ',
        alreadyMember: true,
      ),
    );

    await _openAccept(tester, invites);

    expect(find.text('すでにこのカレンダーに参加しています。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'カレンダーを開く'), findsOneWidget);
  });

  testWidgets('期限切れのリンクは理由を表示し、参加できない', (tester) async {
    final invites = FakeInviteRepository(
      error: const InviteException(
        'この招待リンクは有効期限が切れています。',
        reason: InviteErrorReason.expired,
      ),
    );

    final container = await _openAccept(tester, invites);

    expect(find.text('この招待リンクは有効期限が切れています。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '参加する'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '閉じる'));
    await tester.pumpAndSettle();
    expect(container.read(pendingInviteTokenProvider), isNull);
  });

  testWidgets('取り消し済みのリンクも理由を表示する', (tester) async {
    final invites = FakeInviteRepository(
      error: const InviteException(
        'この招待リンクは取り消されています。',
        reason: InviteErrorReason.revoked,
      ),
    );

    await _openAccept(tester, invites);

    expect(find.text('この招待リンクは取り消されています。'), findsOneWidget);
  });

  testWidgets('使用済みのリンクも理由を表示する', (tester) async {
    final invites = FakeInviteRepository(
      error: const InviteException(
        'この招待リンクは使用済みです。',
        reason: InviteErrorReason.used,
      ),
    );

    await _openAccept(tester, invites);

    expect(find.text('この招待リンクは使用済みです。'), findsOneWidget);
  });

  testWidgets('キャンセルすると受諾待ちを解除する', (tester) async {
    final invites = FakeInviteRepository();
    final container = await _openAccept(tester, invites);

    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();

    expect(invites.calls, ['previewInvite(token-1)']);
    expect(container.read(pendingInviteTokenProvider), isNull);
  });
}

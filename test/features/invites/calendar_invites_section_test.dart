import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/invites/application/invite_providers.dart';
import 'package:kansuke/features/invites/data/invite_repository.dart';
import 'package:kansuke/features/invites/presentation/calendar_invites_section.dart';
import 'package:kansuke/models/models.dart';

import 'fake_invite_repository.dart';

Calendar _calendar({required String ownerId}) {
  return Calendar(
    id: 'shared',
    name: 'わが家',
    memberIds: const ['me', 'other'],
    creatorId: 'me',
    ownerId: ownerId,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );
}

IssuedInvite _issued({required String invitedBy, bool active = true}) {
  return IssuedInvite(
    id: 'invite-1',
    invitedBy: invitedBy,
    expiresAt: DateTime(2026, 7, 2, 9, 30),
    maxUses: 1,
    usedCount: active ? 0 : 1,
    revoked: false,
    active: active,
  );
}

Future<FakeFirebaseFirestore> _seedMembers(Calendar calendar) async {
  final firestore = FakeFirebaseFirestore();
  for (final (id, name) in const [('me', 'ぱぱ'), ('other', 'まま')]) {
    await firestore.collection('users').doc(id).set({
      'name': name,
      'email': '$id@example.com',
      'color': '#1565C0',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }
  // 発行者名を引くメンバー一覧は「自分が参加しているカレンダー」から解決される
  // （users は列挙禁止、Issue #89）。
  await firestore
      .collection('calendars')
      .doc(calendar.id)
      .set(calendar.toFirestore(useServerTimestamp: false));
  return firestore;
}

Future<void> _pumpSection(
  WidgetTester tester,
  FakeInviteRepository invites, {
  required Calendar calendar,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(await _seedMembers(calendar)),
        currentUidProvider.overrideWithValue('me'),
        inviteRepositoryProvider.overrideWithValue(invites),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CalendarInvitesSection(calendar: calendar),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('メンバーは招待リンクを作成でき、リンクをコピーできる（FR-9 / Issue #90）', (tester) async {
    // オーナーでないメンバーでも発行できる。
    final invites = FakeInviteRepository();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpSection(tester, invites, calendar: _calendar(ownerId: 'other'));
    expect(find.text('発行済みの招待リンクはありません'), findsOneWidget);

    await tester.tap(find.text('招待リンクを作成'));
    await tester.pumpAndSettle();

    expect(invites.calls.contains('createInvite(shared)'), isTrue);
    // 発行時にだけトークンを表示する（Firestore にはハッシュしか無い）。
    expect(find.text('kansuke://invite?token=token-1'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'コピー'));
    await tester.pumpAndSettle();

    expect(copied, ['kansuke://invite?token=token-1']);
    expect(find.text('招待リンクをコピーしました'), findsOneWidget);
  });

  testWidgets('発行者本人は自分の招待リンクを取り消せる', (tester) async {
    final invites = FakeInviteRepository(invites: [_issued(invitedBy: 'me')]);

    await _pumpSection(tester, invites, calendar: _calendar(ownerId: 'other'));

    expect(find.textContaining('有効（7/2 09:30まで）'), findsOneWidget);
    expect(find.text('発行: ぱぱ'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取り消し'));
    await tester.pumpAndSettle();

    expect(invites.calls.contains('revokeInvite(invite-1)'), isTrue);
    expect(find.text('招待リンクを取り消しました'), findsOneWidget);
  });

  testWidgets('オーナーは他人が発行した招待リンクも取り消せる', (tester) async {
    final invites = FakeInviteRepository(
      invites: [_issued(invitedBy: 'other')],
    );

    await _pumpSection(tester, invites, calendar: _calendar(ownerId: 'me'));

    await tester.tap(find.widgetWithText(TextButton, '取り消し'));
    await tester.pumpAndSettle();

    expect(invites.calls.contains('revokeInvite(invite-1)'), isTrue);
  });

  testWidgets('発行者でもオーナーでもないメンバーには取り消し導線が出ない', (tester) async {
    final invites = FakeInviteRepository(
      invites: [_issued(invitedBy: 'other')],
    );

    await _pumpSection(tester, invites, calendar: _calendar(ownerId: 'other'));

    expect(find.text('発行: まま'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取り消し'), findsNothing);
  });

  testWidgets('使用済みのリンクは取り消せず、状態を表示する', (tester) async {
    final invites = FakeInviteRepository(
      invites: [_issued(invitedBy: 'me', active: false)],
    );

    await _pumpSection(tester, invites, calendar: _calendar(ownerId: 'me'));

    expect(find.text('使用済み'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取り消し'), findsNothing);
  });
}

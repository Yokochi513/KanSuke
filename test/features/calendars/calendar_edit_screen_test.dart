import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendars/application/calendar_providers.dart';
import 'package:kansuke/features/calendars/data/calendar_membership_repository.dart';
import 'package:kansuke/features/calendars/presentation/calendar_edit_args.dart';
import 'package:kansuke/features/calendars/presentation/calendar_edit_screen.dart';
import 'package:kansuke/models/models.dart';

/// メンバー管理の Callable（Issue #89）を模し、呼び出しを記録する。
class _FakeMembershipRepository implements CalendarMembershipRepository {
  final calls = <String>[];
  CalendarMembershipException? error;

  @override
  Future<void> removeMember({
    required String calendarId,
    required String uid,
  }) => _record('removeMember($calendarId,$uid)');

  @override
  Future<void> leaveCalendar(String calendarId) =>
      _record('leaveCalendar($calendarId)');

  @override
  Future<void> transferOwnership({
    required String calendarId,
    required String uid,
  }) => _record('transferOwnership($calendarId,$uid)');

  Future<void> _record(String call) async {
    calls.add(call);
    final failure = error;
    if (failure != null) throw failure;
  }
}

Future<FakeFirebaseFirestore> _seedMembers() async {
  final firestore = FakeFirebaseFirestore();
  for (final (id, name, color) in const [
    ('me', 'ぱぱ', '#1565C0'),
    ('other', 'まま', '#C2185B'),
  ]) {
    await firestore.collection('users').doc(id).set({
      'name': name,
      'email': '$id@example.com',
      'color': color,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }
  return firestore;
}

/// 参加者 me / other のカレンダーを作る。[ownerId] でオーナーを指定する。
Future<Calendar> _seedCalendar(
  FakeFirebaseFirestore firestore, {
  required String ownerId,
}) async {
  final calendar = Calendar(
    id: 'shared',
    name: '旧名前',
    memberIds: const ['me', 'other'],
    creatorId: 'me',
    ownerId: ownerId,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );
  await firestore
      .collection('calendars')
      .doc(calendar.id)
      .set(calendar.toFirestore(useServerTimestamp: false));
  return calendar;
}

Future<void> _openEditor(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
  CalendarEditArgs args, {
  CalendarMembershipRepository? membership,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue('me'),
        if (membership != null)
          calendarMembershipRepositoryProvider.overrideWithValue(membership),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: RouteSettings(arguments: args),
                    builder: (_) => const CalendarEditScreen(),
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _calendars(
  FakeFirebaseFirestore firestore,
) async {
  final snap = await firestore.collection('calendars').get();
  return snap.docs;
}

void main() {
  testWidgets('新規作成: 名前を入力すると自分だけが参加するカレンダーを作る（Issue #89）', (tester) async {
    final firestore = await _seedMembers();
    await _openEditor(tester, firestore, const CalendarEditArgs.create());

    // メンバーの複数選択 UI は廃止（メンバーは招待リンクで増やす）。
    expect(find.byType(FilterChip), findsNothing);

    await tester.enterText(find.byType(TextFormField), '子供の習い事');
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();

    final data = (await _calendars(firestore)).single.data();
    expect(data['name'], '子供の習い事');
    expect(data['memberIds'], ['me']);
    expect(data['creatorId'], 'me');
    expect(data['ownerId'], 'me');
  });

  testWidgets('オーナーは名前を変更でき、メンバー一覧が色付きで並ぶ', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'me');

    await _openEditor(tester, firestore, CalendarEditArgs.edit(calendar));

    expect(find.text('カレンダーを編集'), findsOneWidget);
    expect(find.text('ぱぱ'), findsOneWidget);
    expect(find.text('まま'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'オーナー'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '新しい名前');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final data = (await _calendars(firestore)).single.data();
    expect(data['name'], '新しい名前');
    // 名前以外は触らない（memberIds / ownerId はクライアントから書けない）。
    expect(data['memberIds'], ['me', 'other']);
    expect(data['ownerId'], 'me');
  });

  testWidgets('オーナー以外は名前を変更できず、メンバー操作の導線も出ない', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'other');

    await _openEditor(tester, firestore, CalendarEditArgs.edit(calendar));

    expect(find.text('カレンダー名を変更できるのはオーナーだけです'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.byType(PopupMenuButton<Object?>), findsNothing);
    // 退出はメンバーでもできる。
    expect(find.text('このカレンダーから退出'), findsOneWidget);
  });

  testWidgets('オーナーはメンバーを削除できる（Callable 経由）', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'me');
    final membership = _FakeMembershipRepository();

    await _openEditor(
      tester,
      firestore,
      CalendarEditArgs.edit(calendar),
      membership: membership,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('カレンダーから削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '削除'));
    await tester.pumpAndSettle();

    expect(membership.calls, ['removeMember(shared,other)']);
  });

  testWidgets('オーナーは他のメンバーへオーナーを移譲できる', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'me');
    final membership = _FakeMembershipRepository();

    await _openEditor(
      tester,
      firestore,
      CalendarEditArgs.edit(calendar),
      membership: membership,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('オーナーにする'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '移譲'));
    await tester.pumpAndSettle();

    expect(membership.calls, ['transferOwnership(shared,other)']);
  });

  testWidgets('退出すると画面を閉じる', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'other');
    final membership = _FakeMembershipRepository();

    await _openEditor(
      tester,
      firestore,
      CalendarEditArgs.edit(calendar),
      membership: membership,
    );

    await tester.tap(find.text('このカレンダーから退出'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await tester.pumpAndSettle();

    expect(membership.calls, ['leaveCalendar(shared)']);
    expect(find.text('カレンダーを編集'), findsNothing);
  });

  testWidgets('退出が拒否されたら理由を表示して画面に留まる（オーナーは移譲が必要）', (tester) async {
    final firestore = await _seedMembers();
    final calendar = await _seedCalendar(firestore, ownerId: 'me');
    final membership = _FakeMembershipRepository()
      ..error = const CalendarMembershipException(
        'オーナーは退出できません。先に他のメンバーへオーナーを移譲してください。',
      );

    await _openEditor(
      tester,
      firestore,
      CalendarEditArgs.edit(calendar),
      membership: membership,
    );

    await tester.tap(find.text('このカレンダーから退出'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await tester.pumpAndSettle();

    expect(find.text('オーナーは退出できません。先に他のメンバーへオーナーを移譲してください。'), findsOneWidget);
    expect(find.text('カレンダーを編集'), findsOneWidget);
  });
}

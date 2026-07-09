import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/calendars/presentation/calendar_edit_args.dart';
import 'package:kansuke/features/calendars/presentation/calendar_edit_screen.dart';
import 'package:kansuke/models/models.dart';

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

Future<void> _openEditor(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
  CalendarEditArgs args,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue('me'),
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
  testWidgets('新規作成: 名前と参加者を選んでカレンダーを保存する', (tester) async {
    final firestore = await _seedMembers();
    await _openEditor(tester, firestore, const CalendarEditArgs.create());

    // 作成者(自分)はデフォルトで選択済み。
    expect(find.widgetWithText(FilterChip, 'ぱぱ'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '子供の習い事');
    await tester.tap(find.widgetWithText(FilterChip, 'まま'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();

    final docs = await _calendars(firestore);
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['name'], '子供の習い事');
    expect(data['memberIds'], ['me', 'other']);
    expect(data['creatorId'], 'me');
  });

  testWidgets('参加者を全員解除するとバリデーションエラーで保存しない', (tester) async {
    final firestore = await _seedMembers();
    await _openEditor(tester, firestore, const CalendarEditArgs.create());

    await tester.enterText(find.byType(TextFormField), '子供の習い事');
    await tester.tap(find.widgetWithText(FilterChip, 'ぱぱ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();

    expect(find.text('参加者を1人以上選択してください'), findsOneWidget);
    expect(await _calendars(firestore), isEmpty);
  });

  testWidgets('既存カレンダーを編集して更新する', (tester) async {
    final firestore = await _seedMembers();
    final calendar = Calendar.create(
      name: '旧名前',
      memberIds: const ['me'],
      creatorId: 'me',
      now: DateTime.utc(2026, 7, 1),
    );
    await firestore
        .collection('calendars')
        .doc(calendar.id)
        .set(calendar.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, CalendarEditArgs.edit(calendar));

    expect(find.text('カレンダーを編集'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '新しい名前');
    await tester.tap(find.widgetWithText(FilterChip, 'まま'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final data = (await _calendars(firestore)).single.data();
    expect(data['name'], '新しい名前');
    expect(data['memberIds'], ['me', 'other']);
  });
}

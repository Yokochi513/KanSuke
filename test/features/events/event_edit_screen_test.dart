import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/events/presentation/event_edit_args.dart';
import 'package:kansuke/features/events/presentation/event_edit_screen.dart';
import 'package:kansuke/models/models.dart';

Future<FakeFirebaseFirestore> _seedMember() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  return firestore;
}

Future<FakeFirebaseFirestore> _seedMembers() async {
  final firestore = await _seedMember();
  await firestore.collection('users').doc('other').set({
    'name': 'まま',
    'email': 'other@example.com',
    'color': '#C2185B',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  return firestore;
}

Future<void> _openEditor(
  WidgetTester tester,
  FakeFirebaseFirestore firestore,
  EventEditArgs args,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
                    builder: (_) => const EventEditScreen(),
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

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _events(
  FakeFirebaseFirestore firestore,
) async {
  final snap = await firestore.collection('events').get();
  return snap.docs;
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('新規作成: UUID採番で予定を保存する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '打ち合わせ');
    await _tapVisible(tester, find.text('作成'));

    final docs = await _events(firestore);
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['title'], '打ち合わせ');
    expect(data['ownerId'], 'me');
    expect(data['updatedBy'], 'me');
    expect(data['type'], 'tentative');
    expect(data['deleted'], false);
    expect(docs.single.id, data['id']); // クライアント生成UUID
  });

  testWidgets('タイトル未入力はバリデーションエラーで保存しない', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await _tapVisible(tester, find.text('作成'));

    expect(find.text('タイトルを入力してください'), findsOneWidget);
    expect(await _events(firestore), isEmpty);
  });

  testWidgets('仮↔確定トグルとリマインドを設定して保存する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '運動会');
    await _tapVisible(tester, find.text('確定'));
    await _tapVisible(tester, find.text('30分前'));
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect(data['type'], 'confirmed');
    expect(data['reminderOffsets'], [30]);
  });

  testWidgets('参加者を複数選択して保存する', (tester) async {
    final firestore = await _seedMembers();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '家族旅行');
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'まま'));
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect(data['participantIds'], ['me', 'other']);
  });

  testWidgets('既存予定を編集して更新する', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final event = Event.create(
      title: '旧タイトル',
      ownerId: 'me',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(event));

    expect(find.text('予定を編集'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '新タイトル');
    await _tapVisible(tester, find.text('保存'));

    final data = (await _events(firestore)).single.data();
    expect(data['title'], '新タイトル');
    expect(data['id'], event.id); // 同一ドキュメント
  });

  testWidgets('編集画面から削除するとソフト削除される', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final event = Event.create(
      title: '消す予定',
      ownerId: 'me',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(event));

    await _tapVisible(tester, find.byIcon(Icons.delete_outline));
    await _tapVisible(tester, find.text('削除'));

    final data = (await _events(firestore)).single.data();
    expect(data['deleted'], true);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
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

/// 参加者の異なる2つのカレンダー（既定＋自分専用）を投入する（FR-8）。
Future<FakeFirebaseFirestore> _seedCalendars(
  FakeFirebaseFirestore firestore,
) async {
  final now = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
  await firestore.collection('calendars').doc(defaultCalendarId).set({
    'name': 'わが家',
    'memberIds': ['me', 'other'],
    'creatorId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  await firestore.collection('calendars').doc('solo').set({
    'name': '自分専用',
    'memberIds': ['me'],
    'creatorId': 'me',
    'createdAt': now,
    'updatedAt': now,
  });
  return firestore;
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
    expect(data['creatorId'], 'me');
    expect(data['participantIds'], ['me']);
    expect(data['updatedBy'], 'me');
    expect(data['type'], 'tentative');
    expect(data['deleted'], false);
    expect(docs.single.id, data['id']); // クライアント生成UUID
  });

  testWidgets('新規作成: 毎月の繰り返しを無限で保存する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '習い事');
    await _tapVisible(tester, find.text('なし'));
    await _tapVisible(tester, find.text('毎月').last);
    await _tapVisible(tester, find.text('作成'));

    final docs = await _events(firestore);
    final data = docs.single.data();

    expect(docs, hasLength(1));
    expect(data['title'], '習い事');
    expect(data['participantIds'], ['me']);
    expect(data['recurrenceFrequency'], 'monthly');
    expect(data['recurrenceCount'], isNull);
    expect(data['id'], docs.single.id); // クライアント生成UUID
  });

  testWidgets('新規作成: 回数指定の毎年繰り返しを数値入力で保存する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '記念日');
    await _tapVisible(tester, find.text('なし'));
    await _tapVisible(tester, find.text('毎年').last);
    await _tapVisible(tester, find.text('回数指定'));
    await tester.enterText(find.widgetWithText(TextFormField, '回数'), '5');
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect(data['recurrenceFrequency'], 'yearly');
    expect(data['recurrenceCount'], 5);
  });

  testWidgets('新規作成: 回数指定が不正なら保存しない', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '記念日');
    await _tapVisible(tester, find.text('なし'));
    await _tapVisible(tester, find.text('毎週').last);
    await _tapVisible(tester, find.text('回数指定'));
    await tester.enterText(find.widgetWithText(TextFormField, '回数'), '0');
    await _tapVisible(tester, find.text('作成'));

    expect(find.text('回数は1以上で入力してください'), findsOneWidget);
    expect(await _events(firestore), isEmpty);
  });

  testWidgets('新規作成: 開始日と終了日を分けて期間予定を保存する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, 'テスト週間');
    await _tapVisible(tester, find.text('終了日'));
    await tester.tap(find.text('8').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect((data['startAt'] as Timestamp).toDate(), DateTime(2026, 7, 5, 9));
    expect((data['endAt'] as Timestamp).toDate(), DateTime(2026, 7, 8, 10));
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

  testWidgets('参加者を全員解除するとバリデーションエラーで保存しない', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '打ち合わせ');
    await _tapVisible(tester, find.widgetWithText(FilterChip, 'ぱぱ'));
    await _tapVisible(tester, find.text('作成'));

    expect(find.text('参加者を1人以上選択してください'), findsOneWidget);
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

  testWidgets('時刻選択は24時間表記の縦スクロールピッカーで更新する', (tester) async {
    final firestore = await _seedMember();
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await _tapVisible(tester, find.widgetWithText(ListTile, '開始時刻'));

    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.mode, CupertinoDatePickerMode.time);
    expect(picker.use24hFormat, true);
    expect(picker.minuteInterval, 1);
    expect(picker.showTimeSeparator, true);

    picker.onDateTimeChanged(DateTime(2026, 7, 5, 13, 45));
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.text('13:45'), findsOneWidget);
  });

  testWidgets('開始時刻を変更すると時間幅を保って終了時刻も更新する', (tester) async {
    final firestore = await _seedMember();
    final originalStartAt = DateTime(2026, 7, 5, 12);
    final event = Event.create(
      title: '昼の予定',
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: originalStartAt,
      endAt: originalStartAt.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: originalStartAt,
      calendarId: defaultCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(event));
    await _tapVisible(tester, find.widgetWithText(ListTile, '開始時刻'));

    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    picker.onDateTimeChanged(DateTime(2026, 7, 5, 17));
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.text('17:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);

    await _tapVisible(tester, find.text('保存'));

    final data = (await _events(firestore)).single.data();
    expect((data['startAt'] as Timestamp).toDate(), DateTime(2026, 7, 5, 17));
    expect((data['endAt'] as Timestamp).toDate(), DateTime(2026, 7, 5, 18));
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
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
      calendarId: defaultCalendarId,
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

  testWidgets('編集画面は作成者を表示し保存しても変更しない', (tester) async {
    final firestore = await _seedMembers();
    final start = DateTime(2026, 7, 5, 9);
    final event = Event.create(
      title: '別の人が入れた予定',
      creatorId: 'other',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'other',
      now: start,
      calendarId: defaultCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(event));

    expect(find.text('作成者: まま'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('作成者: まま'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Align && widget.alignment == Alignment.centerRight,
        ),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).first, 'タイトル変更');
    await _tapVisible(tester, find.text('保存'));

    final data = (await _events(firestore)).single.data();
    expect(data['title'], 'タイトル変更');
    expect(data['creatorId'], 'other');
    expect(data['updatedBy'], 'me');
  });

  testWidgets('編集画面から削除するとソフト削除される', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final event = Event.create(
      title: '消す予定',
      creatorId: 'me',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
      calendarId: defaultCalendarId,
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

  testWidgets('新規作成した予定にはカレンダーIDが保存される', (tester) async {
    final firestore = await _seedCalendars(await _seedMember());
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    await tester.enterText(find.byType(TextFormField).first, '打ち合わせ');
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect(data['calendarId'], defaultCalendarId);
  });

  testWidgets('編集画面にはコピー操作がある', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final event = Event.create(
      title: 'コピー元',
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
      calendarId: defaultCalendarId,
    );
    await firestore
        .collection('events')
        .doc(event.id)
        .set(event.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(event));

    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
  });

  testWidgets('コピー: カレンダーで複数日を選び別UUIDで一括複製し元予定は変えない', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final source = Event.create(
      title: 'コピー元の予定',
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.confirmed,
      memo: 'メモあり',
      reminderOffsets: const [30],
      updatedBy: 'me',
      now: start,
      calendarId: defaultCalendarId,
    );
    await firestore
        .collection('events')
        .doc(source.id)
        .set(source.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(source));

    // コピー操作でコピー先カレンダーが開く。
    await _tapVisible(tester, find.byIcon(Icons.copy_outlined));
    expect(find.text('コピー先の日付を選択'), findsOneWidget);

    // 飛び飛びの2日をタップして選び、「2件コピー」で確定する。
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('2件コピー'));

    final docs = await _events(firestore);
    expect(docs, hasLength(3)); // 元 + コピー2件

    // 元予定は変更されていない。
    final original = docs.firstWhere((doc) => doc.id == source.id).data();
    expect(original['title'], 'コピー元の予定');
    expect((original['startAt'] as Timestamp).toDate(), start);

    // 複製は別 UUID で、選んだ各日へ移動し、日付以外の属性を引き継ぐ。
    final copies = docs
        .where((doc) => doc.id != source.id)
        .map((doc) => doc.data())
        .toList();
    expect(copies, hasLength(2));
    final copyStarts = copies
        .map((copy) => (copy['startAt'] as Timestamp).toDate())
        .toSet();
    expect(copyStarts, {DateTime(2026, 7, 10, 9), DateTime(2026, 7, 20, 9)});
    for (final copy in copies) {
      expect(copy['title'], 'コピー元の予定');
      expect(copy['participantIds'], ['me']);
      expect(copy['type'], 'confirmed');
      expect(copy['memo'], 'メモあり');
      expect(copy['reminderOffsets'], [30]);
      expect(copy['calendarId'], defaultCalendarId);
      // 時間幅は元のまま（1時間）。
      final copyEnd = (copy['endAt'] as Timestamp).toDate();
      final copyStart = (copy['startAt'] as Timestamp).toDate();
      expect(copyEnd.difference(copyStart), const Duration(hours: 1));
    }
  });

  testWidgets('コピー: 繰り返し予定でも単発予定として複製する', (tester) async {
    final firestore = await _seedMember();
    final start = DateTime(2026, 7, 5, 9);
    final source = Event.create(
      title: '毎週の練習',
      creatorId: 'me',
      participantIds: const ['me'],
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      allDay: false,
      type: EventType.tentative,
      memo: '',
      reminderOffsets: const [],
      updatedBy: 'me',
      now: start,
      calendarId: defaultCalendarId,
      recurrenceFrequency: EventRecurrenceFrequency.weekly,
    );
    await firestore
        .collection('events')
        .doc(source.id)
        .set(source.toFirestore(useServerTimestamp: false));

    await _openEditor(tester, firestore, EventEditArgs.edit(source));

    await _tapVisible(tester, find.byIcon(Icons.copy_outlined));
    await tester.tap(find.text('20').last);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('1件コピー'));

    final docs = await _events(firestore);
    expect(docs, hasLength(2));
    final copy = docs.firstWhere((doc) => doc.id != source.id).data();
    expect(copy['recurrenceFrequency'], isNull);
    expect(copy['recurrenceCount'], isNull);
  });

  testWidgets('カレンダーを切り替えると参加者候補がそのカレンダーの参加者に絞り込まれる', (tester) async {
    final firestore = await _seedCalendars(await _seedMembers());
    await _openEditor(
      tester,
      firestore,
      EventEditArgs.create(DateTime(2026, 7, 5)),
    );

    // 既定カレンダー（わが家）では、まま も参加者候補に含まれる。
    expect(find.widgetWithText(FilterChip, 'まま'), findsOneWidget);

    await _tapVisible(tester, find.byType(DropdownButtonFormField<String>));
    await _tapVisible(tester, find.text('自分専用'));

    // 自分専用カレンダーには自分しか参加していないため、まま は候補から消える。
    expect(find.widgetWithText(FilterChip, 'まま'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'ぱぱ'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '一人の予定');
    await _tapVisible(tester, find.text('作成'));

    final data = (await _events(firestore)).single.data();
    expect(data['calendarId'], 'solo');
    expect(data['participantIds'], ['me']);
  });
}

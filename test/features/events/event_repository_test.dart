import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/data/event_repository.dart';
import 'package:kansuke/models/models.dart';

/// テスト用のカレンダー ID（本番の ID は UUID。特別扱いされる固定 ID は無い）。
const testCalendarId = 'test-calendar';

Event _buildEvent({
  required String id,
  required DateTime startAt,
  DateTime? endAt,
  EventType type = EventType.tentative,
  String creatorId = 'creator-1',
  String title = '打ち合わせ',
  String calendarId = testCalendarId,
  EventRecurrenceFrequency? recurrenceFrequency,
  int? recurrenceCount,
}) {
  return Event(
    id: id,
    title: title,
    creatorId: creatorId,
    participantIds: const [],
    startAt: startAt,
    endAt: endAt ?? startAt.add(const Duration(hours: 1)),
    allDay: false,
    type: type,
    memo: '',
    reminderOffsets: const [60],
    updatedBy: creatorId,
    createdAt: startAt,
    updatedAt: startAt,
    deleted: false,
    calendarId: calendarId,
    recurrenceFrequency: recurrenceFrequency,
    recurrenceCount: recurrenceCount,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late EventRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = EventRepository(firestore: firestore);
  });

  Future<Map<String, dynamic>> readRaw(String id) async {
    final doc = await firestore.collection('events').doc(id).get();
    return doc.data()!;
  }

  test('create はクライアント UUID を ID にして書き込み updatedBy を本人にする', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
    );

    await repository.create(event, updatedBy: 'me');

    final raw = await readRaw('evt-1');
    expect(raw['title'], '打ち合わせ');
    expect(raw['updatedBy'], 'me');
    expect(raw['deleted'], false);
    expect(raw['updatedAt'], isA<Timestamp>());
  });

  test('update は作成者を変えずにフィールドと updatedBy を更新する', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
    );
    await repository.create(event, updatedBy: 'me');

    await repository.update(
      event.copyWith(title: '変更後', creatorId: 'creator-2'),
      updatedBy: 'me',
    );

    final raw = await readRaw('evt-1');
    expect(raw['title'], '変更後');
    expect(raw['creatorId'], 'creator-1');
    expect(raw['updatedBy'], 'me');
  });

  test('setType は仮↔確定を type 更新だけで切り替える', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
    );
    await repository.create(event, updatedBy: 'me');

    await repository.setType('evt-1', EventType.confirmed, updatedBy: 'me');

    final raw = await readRaw('evt-1');
    expect(raw['type'], 'confirmed');
    expect(raw['updatedBy'], 'me');
  });

  test('softDelete は deleted=true にし watchRange から除外される', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
    );
    await repository.create(event, updatedBy: 'me');

    await repository.softDelete('evt-1', updatedBy: 'me');

    expect((await readRaw('evt-1'))['deleted'], true);
    final visible = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;
    expect(visible, isEmpty);
  });

  test('watchRange は指定期間に重なる未削除予定のみを startAt 昇順で返す', () async {
    await repository.create(
      _buildEvent(
        id: 'overlap-before',
        startAt: DateTime.utc(2026, 6, 30, 9),
        endAt: DateTime.utc(2026, 7, 2, 10),
      ),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(id: 'in-2', startAt: DateTime.utc(2026, 7, 20, 9)),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(id: 'in-1', startAt: DateTime.utc(2026, 7, 5, 9)),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(id: 'out', startAt: DateTime.utc(2026, 8, 2, 9)),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(
        id: 'ended-before',
        startAt: DateTime.utc(2026, 6, 20, 9),
        endAt: DateTime.utc(2026, 6, 30, 10),
      ),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(id: 'deleted', startAt: DateTime.utc(2026, 7, 6, 9)),
      updatedBy: 'me',
    );
    await repository.softDelete('deleted', updatedBy: 'me');

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;

    expect(events.map((event) => event.id), ['overlap-before', 'in-1', 'in-2']);
  });

  test('watchRange は calendarId が一致する予定だけを返す', () async {
    await repository.create(
      _buildEvent(
        id: 'default-calendar',
        startAt: DateTime.utc(2026, 7, 10, 9),
      ),
      updatedBy: 'me',
    );
    await repository.create(
      _buildEvent(
        id: 'other-calendar',
        startAt: DateTime.utc(2026, 7, 10, 9),
        calendarId: 'calendar-2',
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: 'calendar-2',
        )
        .first;

    expect(events.map((event) => event.id), ['other-calendar']);
  });

  test('watchRange は毎週の無限繰り返しを表示範囲内に展開する', () async {
    await repository.create(
      _buildEvent(
        id: 'weekly',
        title: '習い事',
        startAt: DateTime.utc(2026, 7, 5, 9),
        recurrenceFrequency: EventRecurrenceFrequency.weekly,
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 19),
          end: DateTime.utc(2026, 7, 20),
          calendarId: testCalendarId,
        )
        .first;

    expect(events, hasLength(1));
    expect(events.single.title, '習い事');
    expect(events.single.startAt, DateTime.utc(2026, 7, 19, 9));
    expect(events.single.recurrenceMasterStartAt, DateTime.utc(2026, 7, 5, 9));
  });

  test('watchRange は指定回数を超えた繰り返しを返さない', () async {
    await repository.create(
      _buildEvent(
        id: 'weekly',
        startAt: DateTime.utc(2026, 7, 5, 9),
        recurrenceFrequency: EventRecurrenceFrequency.weekly,
        recurrenceCount: 2,
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 19),
          end: DateTime.utc(2026, 7, 20),
          calendarId: testCalendarId,
        )
        .first;

    expect(events, isEmpty);
  });

  test('watchRange は月末の毎月繰り返しを存在する月末日に丸める', () async {
    await repository.create(
      _buildEvent(
        id: 'monthly',
        startAt: DateTime.utc(2026, 1, 31, 9),
        recurrenceFrequency: EventRecurrenceFrequency.monthly,
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 2, 1),
          end: DateTime.utc(2026, 3, 1),
          calendarId: testCalendarId,
        )
        .first;

    expect(events.single.startAt, DateTime.utc(2026, 2, 28, 9));
  });

  test('watchRange はうるう日の毎年繰り返しを通常年の2月末日に丸める', () async {
    await repository.create(
      _buildEvent(
        id: 'yearly',
        startAt: DateTime.utc(2024, 2, 29, 9),
        recurrenceFrequency: EventRecurrenceFrequency.yearly,
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2025, 2, 1),
          end: DateTime.utc(2025, 3, 1),
          calendarId: testCalendarId,
        )
        .first;

    expect(events.single.startAt, DateTime.utc(2025, 2, 28, 9));
  });

  test('1件の破損ドキュメントがあってもwatchRangeは他の予定を返す', () async {
    await repository.create(
      _buildEvent(id: 'ok', startAt: DateTime.utc(2026, 7, 10, 9)),
      updatedBy: 'me',
    );
    // 型不正など何らかの理由でパースに失敗するドキュメントを模擬する。
    await firestore.collection('events').doc('broken').set({
      'deleted': false,
      'calendarId': testCalendarId,
      'startAt': Timestamp.fromDate(DateTime.utc(2026, 7, 11, 9)),
      'endAt': Timestamp.fromDate(DateTime.utc(2026, 7, 11, 10)),
      'title': 123, // String のはずが不正な型
    });

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;

    expect(events.map((event) => event.id), ['ok']);
  });
}

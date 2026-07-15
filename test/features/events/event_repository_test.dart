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
  List<DateTime> recurrenceExceptions = const [],
  DateTime? recurrenceUntil,
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
    reminderOffsets: {
      creatorId: const [60],
    },
    updatedBy: creatorId,
    createdAt: startAt,
    updatedAt: startAt,
    deleted: false,
    calendarId: calendarId,
    recurrenceFrequency: recurrenceFrequency,
    recurrenceCount: recurrenceCount,
    recurrenceExceptions: recurrenceExceptions,
    recurrenceUntil: recurrenceUntil,
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
      previous: event,
      updatedBy: 'me',
    );

    final raw = await readRaw('evt-1');
    expect(raw['title'], '変更後');
    expect(raw['creatorId'], 'creator-1');
    expect(raw['updatedBy'], 'me');
  });

  // Issue #114: 2 端末がオフラインで別々のフィールドを編集して同期しても、
  // 後着の保存が相手の変更を巻き戻さない（フィールド単位 LWW）。
  test('update は変更したフィールドだけを書き、他端末の別フィールド変更を消さない', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
      title: '元タイトル',
    );
    await repository.create(event, updatedBy: 'me');

    // 端末A: タイトルだけ変更。
    await repository.update(
      event.copyWith(title: '端末Aのタイトル'),
      previous: event,
      updatedBy: 'userA',
    );
    // 端末B: 編集前の値（event）を基準に、メモだけ変更して後着で保存。
    await repository.update(
      event.copyWith(memo: '端末Bのメモ'),
      previous: event,
      updatedBy: 'userB',
    );

    final raw = await readRaw('evt-1');
    // 双方の変更が残る（タイトルは端末A、メモは端末B）。
    expect(raw['title'], '端末Aのタイトル');
    expect(raw['memo'], '端末Bのメモ');
    expect(raw['updatedBy'], 'userB');
  });

  test('update は変更のないフィールドを更新マップに含めない', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
    );
    final data = event
        .copyWith(title: '変更後')
        .toFirestoreUpdate(event, useServerTimestamp: false);

    expect(data.containsKey('title'), isTrue);
    // 変えていないフィールドは載らない。
    expect(data.containsKey('memo'), isFalse);
    expect(data.containsKey('startAt'), isFalse);
    expect(data.containsKey('participantIds'), isFalse);
    expect(data.containsKey('calendarId'), isFalse);
    // 監査用は常に更新する。不変・削除系フィールドは触れない。
    expect(data.containsKey('updatedBy'), isTrue);
    expect(data.containsKey('updatedAt'), isTrue);
    expect(data.containsKey('creatorId'), isFalse);
    expect(data.containsKey('deleted'), isFalse);
    expect(data.containsKey('recurrenceExceptions'), isFalse);
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

  // Issue #115: 端末Aが削除した予定を、端末Bがオフライン編集で保存しても復活しない。
  //
  // #114 以前は編集保存が全フィールド（deleted=false を含む）を書いていたため、
  // 端末Bの後着保存が端末Aの削除（deleted=true）を巻き戻し、削除済み予定が復活して
  // いた。差分更新（toFirestoreUpdate）は deleted を書かないので、後着の編集保存でも
  // deleted は true のまま維持され、watchRange から除外され続ける（基本設計 §4.2）。
  test('update は他端末の並行削除を巻き戻さず、削除済み予定を復活させない', () async {
    final event = _buildEvent(
      id: 'evt-1',
      startAt: DateTime.utc(2026, 7, 10, 9),
      title: '元タイトル',
    );
    await repository.create(event, updatedBy: 'me');

    // 端末A: 予定を削除（ソフト削除）。
    await repository.softDelete('evt-1', updatedBy: 'userA');

    // 端末B: 削除を受け取る前のスナップショット（deleted=false）を基準に、
    // タイトルだけ変更してオフライン編集を後着で保存する。
    await repository.update(
      event.copyWith(title: '端末Bのタイトル'),
      previous: event,
      updatedBy: 'userB',
    );

    final raw = await readRaw('evt-1');
    // タイトルは端末Bの変更が反映されるが、削除フラグは維持される。
    expect(raw['title'], '端末Bのタイトル');
    expect(raw['deleted'], true);

    // 削除済みとして月表示から除外され続ける（復活しない）。
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

  // #86: 「この予定のみ削除」= 例外日の除外。
  test('excludeOccurrence は指定発生日だけを展開から除外する', () async {
    await repository.create(
      _buildEvent(
        id: 'weekly',
        startAt: DateTime.utc(2026, 7, 5, 9),
        recurrenceFrequency: EventRecurrenceFrequency.weekly,
      ),
      updatedBy: 'me',
    );

    // 7/19 の回だけ削除する。
    await repository.excludeOccurrence(
      'weekly',
      DateTime.utc(2026, 7, 19, 9),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;

    final starts = events.map((event) => event.startAt).toList();
    expect(starts, isNot(contains(DateTime.utc(2026, 7, 19, 9))));
    // 前後の回（7/5・7/12・7/26）は残る。
    expect(starts, contains(DateTime.utc(2026, 7, 12, 9)));
    expect(starts, contains(DateTime.utc(2026, 7, 26, 9)));
  });

  // #86: 「これ以降の予定を削除」= 打ち切り日（排他境界）。
  test('truncateRecurrenceFrom は指定発生日以降を展開しない', () async {
    await repository.create(
      _buildEvent(
        id: 'weekly',
        startAt: DateTime.utc(2026, 7, 5, 9),
        recurrenceFrequency: EventRecurrenceFrequency.weekly,
      ),
      updatedBy: 'me',
    );

    // 7/19 以降を削除する（7/19 自身も含まれない）。
    await repository.truncateRecurrenceFrom(
      'weekly',
      DateTime.utc(2026, 7, 19, 9),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;

    expect(events.map((event) => event.startAt), [
      DateTime.utc(2026, 7, 5, 9),
      DateTime.utc(2026, 7, 12, 9),
    ]);
  });

  // #86: 例外日と打ち切り日は同時に効く。
  test('watchRange は例外日を除外しつつ打ち切り日以降も止める', () async {
    await repository.create(
      _buildEvent(
        id: 'weekly',
        startAt: DateTime.utc(2026, 7, 5, 9),
        recurrenceFrequency: EventRecurrenceFrequency.weekly,
        recurrenceExceptions: [DateTime.utc(2026, 7, 12, 9)],
        recurrenceUntil: DateTime.utc(2026, 7, 26, 9),
      ),
      updatedBy: 'me',
    );

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          calendarId: testCalendarId,
        )
        .first;

    // 7/12 は例外、7/26 以降は打ち切り。残るのは 7/5 と 7/19。
    expect(events.map((event) => event.startAt), [
      DateTime.utc(2026, 7, 5, 9),
      DateTime.utc(2026, 7, 19, 9),
    ]);
  });
}

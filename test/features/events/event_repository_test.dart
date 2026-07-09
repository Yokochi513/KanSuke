import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/data/event_repository.dart';
import 'package:kansuke/models/models.dart';

Event _buildEvent({
  required String id,
  required DateTime startAt,
  DateTime? endAt,
  EventType type = EventType.tentative,
  String creatorId = 'creator-1',
  String title = '打ち合わせ',
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
        )
        .first;

    expect(events.map((event) => event.id), ['overlap-before', 'in-1', 'in-2']);
  });

  test('1件の破損ドキュメントがあってもwatchRangeは他の予定を返す', () async {
    await repository.create(
      _buildEvent(id: 'ok', startAt: DateTime.utc(2026, 7, 10, 9)),
      updatedBy: 'me',
    );
    // 型不正など何らかの理由でパースに失敗するドキュメントを模擬する。
    await firestore.collection('events').doc('broken').set({
      'deleted': false,
      'startAt': Timestamp.fromDate(DateTime.utc(2026, 7, 11, 9)),
      'endAt': Timestamp.fromDate(DateTime.utc(2026, 7, 11, 10)),
      'title': 123, // String のはずが不正な型
    });

    final events = await repository
        .watchRange(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
        )
        .first;

    expect(events.map((event) => event.id), ['ok']);
  });
}

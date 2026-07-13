import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/calendars/data/calendar_repository.dart';
import 'package:kansuke/models/models.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late CalendarRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = CalendarRepository(firestore: firestore);
  });

  Future<Map<String, dynamic>> readRaw(String id) async {
    final doc = await firestore.collection('calendars').doc(id).get();
    return doc.data()!;
  }

  test('create はクライアント UUID を ID にして書き込む', () async {
    final calendar = Calendar.create(
      name: '子供の習い事',
      memberIds: const ['me'],
      creatorId: 'me',
      now: DateTime.utc(2026, 7, 1),
    );

    await repository.create(calendar);

    final raw = await readRaw(calendar.id);
    expect(raw['name'], '子供の習い事');
    expect(raw['memberIds'], ['me']);
    expect(raw['creatorId'], 'me');
    // 作成者がそのままオーナーになる（Issue #89）。
    expect(raw['ownerId'], 'me');
  });

  test('updateName は名前だけを更新し、メンバー・オーナーには触れない（Issue #89）', () async {
    final calendar = Calendar.create(
      name: '旧名前',
      memberIds: const ['me', 'other'],
      creatorId: 'me',
      now: DateTime.utc(2026, 7, 1),
    );
    await repository.create(calendar);

    await repository.updateName(calendar.id, '新しい名前');

    final raw = await readRaw(calendar.id);
    expect(raw['name'], '新しい名前');
    expect(raw['memberIds'], ['me', 'other']);
    expect(raw['ownerId'], 'me');
  });

  test('watchMine は自分が参加しているカレンダーだけを返す', () async {
    await repository.create(
      Calendar.create(
        name: '参加中',
        memberIds: const ['me'],
        creatorId: 'me',
        now: DateTime.utc(2026, 7, 1),
      ),
    );
    await repository.create(
      Calendar.create(
        name: '未参加',
        memberIds: const ['other'],
        creatorId: 'other',
        now: DateTime.utc(2026, 7, 1),
      ),
    );

    final calendars = await repository.watchMine('me').first;

    expect(calendars.map((c) => c.name), ['参加中']);
  });
}

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
  });

  test('updateNameAndMembers は名前と参加者を更新する', () async {
    final calendar = Calendar.create(
      name: '旧名前',
      memberIds: const ['me'],
      creatorId: 'me',
      now: DateTime.utc(2026, 7, 1),
    );
    await repository.create(calendar);

    await repository.updateNameAndMembers(
      calendar.id,
      name: '新しい名前',
      memberIds: const ['me', 'other'],
    );

    final raw = await readRaw(calendar.id);
    expect(raw['name'], '新しい名前');
    expect(raw['memberIds'], ['me', 'other']);
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

  test('ensureDefaultCalendar は未作成なら既知の全メンバーを含めて作成する', () async {
    await repository.ensureDefaultCalendar(
      uid: 'me',
      knownMemberIds: ['me', 'other'],
    );

    final raw = await readRaw(defaultCalendarId);
    expect(raw['name'], 'わが家');
    expect((raw['memberIds'] as List).toSet(), {'me', 'other'});
    expect(raw['creatorId'], 'me');
  });

  test('ensureDefaultCalendar は既に存在するなら既存メンバーを維持して自分を追加する', () async {
    await repository.ensureDefaultCalendar(uid: 'me', knownMemberIds: ['me']);

    await repository.ensureDefaultCalendar(
      uid: 'other',
      knownMemberIds: ['me', 'other'],
    );

    final raw = await readRaw(defaultCalendarId);
    expect((raw['memberIds'] as List).toSet(), {'me', 'other'});
    // 2回目以降は creatorId・name を変更しない。
    expect(raw['creatorId'], 'me');
    expect(raw['name'], 'わが家');
  });

  test('ensureDefaultCalendar は既に参加済みなら何もしない', () async {
    await repository.ensureDefaultCalendar(uid: 'me', knownMemberIds: ['me']);

    await repository.ensureDefaultCalendar(uid: 'me', knownMemberIds: ['me']);

    final raw = await readRaw(defaultCalendarId);
    expect((raw['memberIds'] as List), ['me']);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/users/data/user_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = UserRepository(firestore: firestore);
  });

  Future<void> seedUser(String uid, String name, String color) {
    return firestore.collection('users').doc(uid).set({
      'name': name,
      'email': '$uid@example.com',
      'color': color,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });
  }

  test('watchUsers は指定した uid のメンバーだけを名前昇順で色・名前付きで返す', () async {
    await seedUser('u2', 'ぱぱ', '#1565C0');
    await seedUser('u1', 'あかね', '#D84315');
    // users は列挙禁止（Issue #89）。参加カレンダーのメンバー以外は取得しない。
    await seedUser('u3', 'よそのひと', '#2E7D32');

    // uid ごとの購読が届いた順に流れるため、全員そろった時点を待つ。
    final members = await repository
        .watchUsers(['u1', 'u2'])
        .firstWhere((members) => members.length == 2);

    expect(members.map((m) => m.name), ['あかね', 'ぱぱ']);
    expect(members.first.color, '#D84315');
  });

  test('watchUsers は存在しない uid を無視する', () async {
    await seedUser('u1', 'あかね', '#D84315');

    final members = await repository
        .watchUsers(['u1', 'missing'])
        .firstWhere((members) => members.isNotEmpty);

    expect(members.map((m) => m.id), ['u1']);
  });

  test('watchUsers は uid が空なら空リストを返す', () async {
    expect(await repository.watchUsers(const []).first, isEmpty);
  });

  test('watchUser は存在すればメンバー、なければ null を返す', () async {
    await seedUser('u1', 'あかね', '#D84315');

    expect((await repository.watchUser('u1').first)?.name, 'あかね');
    expect(await repository.watchUser('missing').first, isNull);
  });

  test('updateName は表示名を更新する', () async {
    await seedUser('u1', 'あかね', '#D84315');

    await repository.updateName('u1', 'あかねママ');

    final doc = await firestore.collection('users').doc('u1').get();
    expect(doc.data()!['name'], 'あかねママ');
  });
}

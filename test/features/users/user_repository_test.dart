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

  test('watchMembers は家族メンバーを名前昇順で色・名前付きで返す', () async {
    await seedUser('u2', 'ぱぱ', '#1565C0');
    await seedUser('u1', 'あかね', '#D84315');

    final members = await repository.watchMembers().first;

    expect(members.map((m) => m.name), ['あかね', 'ぱぱ']);
    expect(members.first.color, '#D84315');
  });

  test('watchUser は存在すればメンバー、なければ null を返す', () async {
    await seedUser('u1', 'あかね', '#D84315');

    expect((await repository.watchUser('u1').first)?.name, 'あかね');
    expect(await repository.watchUser('missing').first, isNull);
  });
}

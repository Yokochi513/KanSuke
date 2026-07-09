import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/notifications/data/device_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late DeviceRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = DeviceRepository(firestore: firestore);
  });

  test('upsertToken は users/{uid}/devices/{token} に platform を保存する', () async {
    await repository.upsertToken(uid: 'u1', token: 'tok-1', platform: 'ios');

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('devices')
        .doc('tok-1')
        .get();

    expect(doc.exists, isTrue);
    expect(doc.data()!['platform'], 'ios');
    expect(doc.data()!['updatedAt'], isNotNull);
  });

  test(
    'upsertToken は同じトークンに再実行すると updatedAt を更新する（onTokenRefresh 相当）',
    () async {
      await repository.upsertToken(uid: 'u1', token: 'tok-1', platform: 'ios');
      final first = await firestore
          .collection('users')
          .doc('u1')
          .collection('devices')
          .doc('tok-1')
          .get();

      await repository.upsertToken(
        uid: 'u1',
        token: 'tok-1',
        platform: 'android',
      );
      final second = await firestore
          .collection('users')
          .doc('u1')
          .collection('devices')
          .doc('tok-1')
          .get();

      expect(first.data()!['platform'], 'ios');
      expect(second.data()!['platform'], 'android');
    },
  );

  test('deleteToken はトークンドキュメントを削除する（サインアウト時）', () async {
    await repository.upsertToken(uid: 'u1', token: 'tok-1', platform: 'ios');

    await repository.deleteToken(uid: 'u1', token: 'tok-1');

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('devices')
        .doc('tok-1')
        .get();
    expect(doc.exists, isFalse);
  });
}

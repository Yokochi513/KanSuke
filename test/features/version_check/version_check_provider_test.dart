import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/version_check/application/version_check_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'KanSuke',
      packageName: 'com.example.kansuke',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('isNewerVersion', () {
    test('remote が local より大きければ true', () {
      expect(isNewerVersion('1.1.0', '1.0.0'), isTrue);
    });

    test('remote が local と同じなら false', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('remote が local より小さければ false', () {
      expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('桁数が異なっても不足分を0として比較する', () {
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.1', '1.2'), isTrue);
    });
  });

  group('versionUpdateNoticeProvider', () {
    Future<ProviderContainer> buildContainer(
      FakeFirebaseFirestore firestore,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('meta/release が無ければ通知しない', () async {
      final container = await buildContainer(FakeFirebaseFirestore());

      final release = await container.read(versionUpdateNoticeProvider.future);

      expect(release, isNull);
    });

    test('新しいバージョンがあれば ReleaseInfo を返す', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('meta/release').set({
        'version': '1.1.0',
        'notes': '新機能を追加しました',
      });
      final container = await buildContainer(firestore);

      final release = await container.read(versionUpdateNoticeProvider.future);

      expect(release?.version, '1.1.0');
      expect(release?.notes, '新機能を追加しました');
    });

    test('既読バージョンなら再通知しない', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('meta/release').set({
        'version': '1.1.0',
        'notes': '',
      });
      SharedPreferences.setMockInitialValues({
        'version_check.last_seen_version': '1.1.0',
      });
      final container = ProviderContainer(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
      );
      addTearDown(container.dispose);

      final release = await container.read(versionUpdateNoticeProvider.future);

      expect(release, isNull);
    });
  });
}

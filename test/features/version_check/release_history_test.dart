import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/version_check/application/version_check_provider.dart';
import 'package:kansuke/features/version_check/presentation/release_history_screen.dart';

Future<FakeFirebaseFirestore> _seedReleases() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('releases').doc('1.9.0').set({
    'version': '1.9.0',
    'notes': '古い機能を追加しました',
    'publishedAt': Timestamp.fromDate(DateTime(2026, 7, 9)),
  });
  await firestore.collection('releases').doc('1.10.0').set({
    'version': '1.10.0',
    'notes': '新しい機能を追加しました',
    'publishedAt': Timestamp.fromDate(DateTime(2026, 7, 13)),
  });
  return firestore;
}

void main() {
  test('releaseHistoryProvider はバージョン降順で返す（文字列順ではない）', () async {
    final firestore = await _seedReleases();
    final container = ProviderContainer(
      overrides: [firestoreProvider.overrideWithValue(firestore)],
    );
    addTearDown(container.dispose);

    // 購読していないストリームは値を流さないため、先に listen する。
    container.listen(releaseHistoryProvider, (_, _) {});
    final releases = await container.read(releaseHistoryProvider.future);

    expect(releases.map((release) => release.version), ['1.10.0', '1.9.0']);
    expect(releases.first.notes, '新しい機能を追加しました');
    expect(releases.first.publishedAt, DateTime(2026, 7, 13));
  });

  testWidgets('更新履歴画面に全バージョンのリリースノートが新しい順に並ぶ', (tester) async {
    final firestore = await _seedReleases();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(home: ReleaseHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final versions = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^v1\.')))
        .map((text) => text.data);
    expect(versions, ['v1.10.0', 'v1.9.0']);
    expect(find.text('新しい機能を追加しました'), findsOneWidget);
    expect(find.text('古い機能を追加しました'), findsOneWidget);
    expect(find.text('2026年7月13日'), findsOneWidget);
  });

  testWidgets('履歴が無ければその旨を表示する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
        child: const MaterialApp(home: ReleaseHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更新履歴はまだありません。'), findsOneWidget);
  });
}

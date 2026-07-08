import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/version_check/presentation/version_check_gate.dart';
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

  testWidgets('新しいバージョンがあると起動時にダイアログを表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('meta/release').set({
      'version': '1.1.0',
      'notes': '新機能を追加しました',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(
          home: VersionCheckGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新しいバージョンがあります'), findsOneWidget);
    expect(find.textContaining('新機能を追加しました'), findsOneWidget);
  });

  testWidgets('端末バージョンと同じなら通知しない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('meta/release').set({'version': '1.0.0', 'notes': ''});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(
          home: VersionCheckGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新しいバージョンがあります'), findsNothing);
  });

  testWidgets('閉じると同一バージョンでは再表示しない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    await firestore.doc('meta/release').set({'version': '1.1.0', 'notes': ''});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(
          home: VersionCheckGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新しいバージョンがあります'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
        child: const MaterialApp(
          home: VersionCheckGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新しいバージョンがあります'), findsNothing);
  });
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/theme.dart';
import 'package:kansuke/core/color_utils.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/auth/data/auth_repository.dart';
import 'package:kansuke/features/settings/application/notification_permission.dart';
import 'package:kansuke/features/settings/presentation/settings_screen.dart';

Future<FakeFirebaseFirestore> _seedUser() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('me').set({
    'name': 'ぱぱ',
    'email': 'me@example.com',
    'color': '#1565C0',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  });
  return firestore;
}

void main() {
  testWidgets('自分の色を選ぶと users/{uid}.color が更新される', (tester) async {
    final firestore = await _seedUser();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue('me'),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 2 番目のパレット色を選ぶ。
    await tester.tap(find.byType(InkResponse).at(1));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('users').doc('me').get();
    expect(doc.data()!['color'], hexFromColor(MemberColors.palette[1]));
  });

  testWidgets('通知許可の状態表示と要求導線が動く', (tester) async {
    final firestore = await _seedUser();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue('me'),
          notificationPermissionGatewayProvider.overrideWithValue(
            _FakeGateway(afterRequest: NotificationPermissionStatus.granted),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('状態: 未設定'), findsOneWidget);

    await tester.tap(find.text('許可をリクエスト'));
    await tester.pumpAndSettle();

    expect(find.text('状態: 許可済み'), findsOneWidget);
  });

  testWidgets('サインアウトできる', (tester) async {
    final firestore = await _seedUser();
    final auth = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue('me'),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('サインアウト'));
    await tester.pumpAndSettle();

    expect(auth.signOutCount, 1);
  });
}

class _FakeGateway implements NotificationPermissionGateway {
  _FakeGateway({required this.afterRequest});

  final NotificationPermissionStatus afterRequest;

  @override
  Future<NotificationPermissionStatus> current() async =>
      NotificationPermissionStatus.notDetermined;

  @override
  Future<NotificationPermissionStatus> request() async => afterRequest;
}

class _FakeAuthRepository implements AuthRepository {
  int signOutCount = 0;

  @override
  Stream<AuthSession?> authStateChanges() =>
      Stream.value(const AuthSession(uid: 'me'));

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> initializeGoogleSignIn() async {}

  @override
  Stream<AuthException?> get googleWebSignInResults =>
      const Stream<AuthException?>.empty();

  @override
  Future<void> signOut() async => signOutCount++;
}

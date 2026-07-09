import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/app/routes.dart';
import 'package:kansuke/app/theme.dart';
import 'package:kansuke/core/color_utils.dart';
import 'package:kansuke/core/firebase_providers.dart';
import 'package:kansuke/features/auth/application/auth_state.dart';
import 'package:kansuke/features/auth/data/auth_repository.dart';
import 'package:kansuke/features/notifications/application/notification_providers.dart';
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

    expect(MemberColors.palette, hasLength(6));

    final secondPaletteColor = MemberColors.palette[1];
    await tester.tap(
      find.byKey(ValueKey('member-color-${hexFromColor(secondPaletteColor)}')),
    );
    await tester.pumpAndSettle();

    final doc = await firestore.collection('users').doc('me').get();
    expect(doc.data()!['color'], hexFromColor(secondPaletteColor));
  });

  testWidgets('カスタム色を選ぶと users/{uid}.color が更新される', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('member-custom-color')));
    await tester.pumpAndSettle();

    expect(find.text('色を選択'), findsOneWidget);

    tester.widget<Slider>(find.byType(Slider).at(0)).onChanged!(255);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider).at(1)).onChanged!(51);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider).at(2)).onChanged!(102);
    await tester.pump();

    expect(find.text('#FF3366'), findsOneWidget);

    await tester.tap(find.text('決定'));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('users').doc('me').get();
    expect(doc.data()!['color'], '#FF3366');
  });

  testWidgets('自分の名前を変更すると users/{uid}.name が更新される', (tester) async {
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

    expect(find.text('ぱぱ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'あかねママ');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('users').doc('me').get();
    expect(doc.data()!['name'], 'あかねママ');
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
          deviceRegistrationServiceProvider.overrideWithValue(
            _FakeDeviceRegistrationService(),
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
    // FR-8: カレンダーセクション追加で一覧が伸びたため、既定のテスト表示領域では
    // 末尾の要素がリストの描画範囲外になる。ensureVisible が要素を見つけられる
    // よう表示領域を広げる。
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    await tester.ensureVisible(find.text('サインアウト'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('サインアウト'));
    await tester.pumpAndSettle();

    expect(auth.signOutCount, 1);
  });

  testWidgets('カレンダー管理をタップすると管理画面へ遷移する', (tester) async {
    final firestore = await _seedUser();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue('me'),
        ],
        child: MaterialApp(
          home: const SettingsScreen(),
          routes: {
            AppRoutes.calendarManagement: (_) =>
                const Scaffold(body: Text('CALENDAR_MANAGEMENT')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('カレンダー管理'));
    await tester.pumpAndSettle();

    expect(find.text('CALENDAR_MANAGEMENT'), findsOneWidget);
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

class _FakeDeviceRegistrationService implements DeviceRegistrationService {
  @override
  Future<void> registerCurrentToken(String uid) async {}

  @override
  Future<void> unregisterForSignOut(String uid) async {}
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

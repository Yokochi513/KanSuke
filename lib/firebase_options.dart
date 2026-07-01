// Generated-style placeholder configuration for FlutterFire.
// Run `flutterfire configure` for the target Firebase project before launch.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase options are not configured for web.');
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'Firebase options are only configured for Android and iOS.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'replace-with-android-api-key',
    appId: '1:000000000000:android:replace-with-app-id',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
    storageBucket: 'replace-with-firebase-project-id.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'replace-with-ios-api-key',
    appId: '1:000000000000:ios:replace-with-app-id',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
    storageBucket: 'replace-with-firebase-project-id.firebasestorage.app',
    iosBundleId: 'com.kansuke.kansuke',
  );
}

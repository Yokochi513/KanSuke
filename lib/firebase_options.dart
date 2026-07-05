// Generated-style placeholder configuration for FlutterFire.
// Run `flutterfire configure` for the target Firebase project before launch.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'Firebase options are only configured for Android, iOS and Web.',
      ),
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCbAvaNVhpAVnvmXg3z_4Pe34E9iuaOqpw',
    appId: '1:271795308120:web:928229a89d3836ff3f2c2d',
    messagingSenderId: '271795308120',
    projectId: 'kansuke-b6d32',
    authDomain: 'kansuke-b6d32.firebaseapp.com',
    storageBucket: 'kansuke-b6d32.firebasestorage.app',
    measurementId: 'G-1JSREWMNB1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAYG7mJYYBOwZmPG6WJHoSalXu4gcJesPA',
    appId: '1:271795308120:android:73f60bfb4faf5b3a3f2c2d',
    messagingSenderId: '271795308120',
    projectId: 'kansuke-b6d32',
    storageBucket: 'kansuke-b6d32.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDS6eXW2cQ504y1urjwlK3oK3cRggxyyGM',
    appId: '1:271795308120:ios:f5adb95971a78d623f2c2d',
    messagingSenderId: '271795308120',
    projectId: 'kansuke-b6d32',
    storageBucket: 'kansuke-b6d32.firebasestorage.app',
    iosBundleId: 'com.kansuke.kansuke',
  );
}

import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  Future<void>? _googleInitialization;

  @override
  Stream<AuthSession?> authStateChanges() {
    return _auth.authStateChanges().map(
      (user) => user == null ? null : AuthSession(uid: user.uid),
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await (_googleInitialization ??= _googleSignIn.initialize());
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      await _verifyUserDocument(result.user);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelledException();
      }
      throw const AuthException();
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseException(error);
    } on FirebaseException catch (error) {
      throw _mapFirebaseException(error);
    }
  }

  @override
  Future<void> signInWithApple() async {
    final rawNonce = _createNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final identityToken = appleCredential.identityToken;
      if (identityToken == null) {
        throw const AuthException();
      }

      final fullName = AppleFullPersonName(
        givenName: appleCredential.givenName,
        familyName: appleCredential.familyName,
      );
      final credential = AppleAuthProvider.credentialWithIDToken(
        identityToken,
        rawNonce,
        fullName,
      );
      final result = await _auth.signInWithCredential(credential);
      await _verifyUserDocument(result.user);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AuthCancelledException();
      }
      throw const AuthException();
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseException(error);
    } on FirebaseException catch (error) {
      throw _mapFirebaseException(error);
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await (_googleInitialization ??= _googleSignIn.initialize());
      await _googleSignIn.signOut();
    } on GoogleSignInException {
      // Firebase のセッションは既に破棄済み。Google 側の未接続は無視できる。
    }
  }

  Future<void> _verifyUserDocument(User? user) async {
    if (user == null) {
      throw const AuthException();
    }

    // NFR-4 / 基本設計 §2.1:
    // users/{uid} の生成は allowlist を参照できる Functions 側に集約し、
    // クライアントは認証完了後に存在確認だけを行う。
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    if (!snapshot.exists) {
      await _auth.signOut();
      throw const AuthAccessDeniedException();
    }
  }

  AuthException _mapFirebaseException(FirebaseException error) {
    if (const {'permission-denied', 'invalid-argument'}.contains(error.code)) {
      return const AuthAccessDeniedException();
    }
    return const AuthException();
  }

  String _createNonce([int length = 32]) {
    const characters =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }
}

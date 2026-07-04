import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリ全体で共有する Firestore インスタンス。
///
/// 基本設計 §6.2: Firestore SDK のローカルキャッシュをそのまま利用する。
/// テストでは fake_cloud_firestore を override して差し込む。
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

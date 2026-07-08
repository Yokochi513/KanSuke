import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';

const _logTag = 'ReleaseInfoRepository';

/// リリース時に CI が `meta/release` へ書き込む最新バージョン情報（FR-7）。
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes});

  final String version;
  final String notes;
}

/// `meta/release` ドキュメントを読み取る（読み取り専用。書き込みは CI 側の
/// Admin SDK が行う。`firestore.rules` も書き込みルールを持たない）。
class ReleaseInfoRepository {
  ReleaseInfoRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// 最新のリリース情報を取得する。ドキュメントが存在しない場合や取得に
  /// 失敗した場合は `null` を返す（バージョン通知は必須機能ではないため、
  /// 起動を妨げない）。
  Future<ReleaseInfo?> fetchLatest() async {
    try {
      final snapshot = await _firestore.doc('meta/release').get();
      final data = snapshot.data();
      if (data == null) return null;
      final version = data['version'];
      if (version is! String) return null;
      final notes = data['notes'];
      return ReleaseInfo(version: version, notes: notes is String ? notes : '');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to fetch meta/release',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

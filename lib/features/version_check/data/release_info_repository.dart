import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';

const _logTag = 'ReleaseInfoRepository';

/// リリース時に CI が Firestore へ書き込むバージョン情報（FR-7）。
///
/// 最新 1 件は起動時のお知らせ用に `meta/release` に、履歴は更新履歴画面用に
/// `releases/{version}` に書かれる（Issue #96）。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    this.publishedAt,
  });

  final String version;
  final String notes;

  /// 公開日時。CI が書き込む（過去バージョンは CHANGELOG.md の日付）。
  final DateTime? publishedAt;
}

/// リリース情報を読み取る（読み取り専用。書き込みは CI 側の Admin SDK が行う。
/// `firestore.rules` も書き込みルールを持たない）。
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
      return _toReleaseInfo(data);
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

  /// 全バージョンの更新履歴を監視する（Issue #96）。並び順は呼び出し側で決める。
  ///
  /// `snapshots()` はローカルキャッシュ起点で流れるため、オフラインでも一度
  /// 取得済みの履歴は表示できる（NFR-3）。
  Stream<List<ReleaseInfo>> watchHistory() {
    return _firestore.collection('releases').snapshots().map((snapshot) {
      final releases = <ReleaseInfo>[];
      for (final doc in snapshot.docs) {
        final release = _toReleaseInfo(doc.data());
        if (release != null) releases.add(release);
      }
      return releases;
    });
  }

  ReleaseInfo? _toReleaseInfo(Map<String, dynamic> data) {
    final version = data['version'];
    if (version is! String) return null;
    final notes = data['notes'];
    final publishedAt = data['publishedAt'];
    return ReleaseInfo(
      version: version,
      notes: notes is String ? notes : '',
      publishedAt: publishedAt is Timestamp ? publishedAt.toDate() : null,
    );
  }
}

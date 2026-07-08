import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase_providers.dart';
import '../data/release_info_repository.dart';

const _lastSeenVersionKey = 'version_check.last_seen_version';

final releaseInfoRepositoryProvider = Provider<ReleaseInfoRepository>((ref) {
  return ReleaseInfoRepository(firestore: ref.watch(firestoreProvider));
});

/// ドット区切りの数値バージョンを比較し、[remote] が [local] より新しいかを返す。
/// 桁数が異なる場合は不足分を 0 として扱う（例: "1.2" と "1.2.0" は同一）。
bool isNewerVersion(String remote, String local) {
  final remoteParts = remote.split('.').map(int.tryParse).toList();
  final localParts = local.split('.').map(int.tryParse).toList();
  final length = remoteParts.length > localParts.length
      ? remoteParts.length
      : localParts.length;
  for (var i = 0; i < length; i++) {
    final r = i < remoteParts.length ? (remoteParts[i] ?? 0) : 0;
    final l = i < localParts.length ? (localParts[i] ?? 0) : 0;
    if (r != l) return r > l;
  }
  return false;
}

/// 起動時に一度だけ評価する（FR-7）。Firestore 上に端末より新しいバージョンが
/// あり、かつ当該バージョンをまだ通知していない場合に [ReleaseInfo] を返す。
final versionUpdateNoticeProvider = FutureProvider<ReleaseInfo?>((ref) async {
  final release = await ref.watch(releaseInfoRepositoryProvider).fetchLatest();
  if (release == null) return null;

  final packageInfo = await PackageInfo.fromPlatform();
  if (!isNewerVersion(release.version, packageInfo.version)) return null;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_lastSeenVersionKey) == release.version) return null;

  return release;
});

/// ダイアログを閉じた際に、当該バージョンを既読として記録する。
Future<void> markVersionAsSeen(String version) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastSeenVersionKey, version);
}

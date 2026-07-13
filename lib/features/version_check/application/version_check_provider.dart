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

/// 更新履歴（全バージョンのリリースノート）をバージョン降順で流す（FR-7 / Issue #96）。
///
/// 並べ替えはクライアント側で行う。ドキュメント ID がバージョンのため文字列順では
/// "1.10.0" < "1.9.0" となってしまい、数値としての比較が必要なため。
final releaseHistoryProvider = StreamProvider<List<ReleaseInfo>>((ref) {
  return ref.watch(releaseInfoRepositoryProvider).watchHistory().map((
    releases,
  ) {
    final sorted = [...releases];
    sorted.sort((a, b) {
      if (isNewerVersion(a.version, b.version)) return -1;
      if (isNewerVersion(b.version, a.version)) return 1;
      return 0;
    });
    return sorted;
  });
});

/// 端末にインストールされているアプリのバージョン（設定画面の表示用）。
final appVersionProvider = FutureProvider<String>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
});

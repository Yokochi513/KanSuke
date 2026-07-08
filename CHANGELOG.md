# Changelog

すべての注目すべき変更はこのファイルに記録する。

運用ルール（FR-7）: develop → main へのリリース PR を作成する際、`## [Unreleased]`
を `## [x.y.z] - YYYY-MM-DD`（`pubspec.yaml` の新バージョンと一致させる）にリネームし、
先頭に新しい空の `## [Unreleased]` を追加してからマージする。main への push を検知して
CI がこのファイルから該当バージョンのリリースノートを読み取り、Firestore の
`meta/release` に反映する。

## [Unreleased]
- (次回リリースまでの変更点をここに追記)

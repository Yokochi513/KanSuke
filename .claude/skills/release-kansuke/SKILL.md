---
name: release-kansuke
description: Prepare a KanSuke release — bump the version, finalize CHANGELOG.md, build the signed Android release App Bundle (AAB), and open the develop → main release PR. Use when asked to cut, prepare, or ship a KanSuke release (e.g. "v1.3.0 をリリースして", "リリース PR を作って").
---

# KanSuke リリース手順

`develop` の内容を `main` へ出すためのリリース準備を行う。担当範囲は **リリース PR の作成まで**。
PR のマージ、`main` → `develop` の back-merge、アプリの家族への配布は**人間が行う**（本 skill では実行しない）。
リリース全体の運用手順は [docs/運用/リリース手順.md](../../../docs/運用/リリース手順.md) が正典。手順に迷ったら先にそれを読む。

成果物は 3 つ:

1. `CHANGELOG.md` + `pubspec.yaml` のリリース用更新
2. 署名済み Android リリース App Bundle（AAB / ローカルビルド）
3. `release/x.y.z` → `main` のリリース PR

## 1. 事前確認

- `git status` がクリーンで、`develop` の最新（`git fetch && git status` で origin/develop と同期済み）であること。未コミットの変更があれば作業を止めてユーザーに確認する。
- `gh auth status` が通ること。
- 前回リリース以降の変更を把握する: `git log --oneline main..develop` と `gh pr list --state merged --base develop --limit 20`。

## 2. バージョン決定

`pubspec.yaml` の `version: x.y.z+N` を確認し、次バージョンを決める（semver）:

- 機能追加あり → マイナー上げ（1.2.0 → 1.3.0）
- 修正のみ → パッチ上げ（1.2.0 → 1.2.1）
- ビルド番号 `+N` は毎リリース 1 ずつ増やす（1.2.0+3 → 1.3.0+4）

**決定したバージョンは着手前にユーザーへ提示して合意を取る。** 迷ったら推測せず尋ねる。

## 3. リリースブランチ

`develop` から `release/x.y.z` を切る（例 `release/1.3.0`）。

## 4. CHANGELOG.md（FR-7）

`CHANGELOG.md` 冒頭の運用ルールに従う:

- `## [Unreleased]` を `## [x.y.z] - YYYY-MM-DD`（`pubspec.yaml` の新バージョンと一致、日付は today）にリネーム
- その上に**新しい空の `## [Unreleased]`** を追加
- `[Unreleased]` の項目が実際のマージ内容を網羅しているか `git log main..develop` と突き合わせ、漏れがあれば追記する

書き方は既存エントリに合わせる: **利用者目線の日本語 1 行、「〜できるようになりました」「〜を修正しました」調**。Issue 番号や実装用語（Riverpod, Firestore など）は書かない。この文面は CI（`publish-release-version.yml`）が Firestore `meta/release` に載せ、アプリ内のお知らせとして家族が読むもの。

`pubspec.yaml` の `version:` も新バージョンに更新する。

## 5. 検証

```bash
flutter pub get
flutter analyze                                   # 警告ゼロを維持
dart format --output=none --set-exit-if-changed .
flutter test
```

`functions/` に変更が含まれるリリースなら `npm --prefix functions ci && npm --prefix functions run lint && npm --prefix functions test` も実行する。

## 6. Android リリース App Bundle（AAB）ビルド

```bash
flutter build appbundle --release
```

- 出力: `build/app/outputs/bundle/release/app-release.aab`
- リリース署名鍵（`android/key.properties` → `kansuke-release-key.jks`）で署名される。`android/key.properties` が無いとデバッグ署名になり、**インストール済みアプリを署名不一致で上書きできなくなる**。ビルド前にファイルの存在を確認し、無ければ止めてユーザーに知らせる。
- ビルド後、AAB のパスとサイズ、`versionName` が新バージョンになっていることを報告する。
- AAB は端末に直接インストールできない形式（Play Console へのアップロード用）。端末へ直接入れる必要がある場合は `bundletool` で APKS に変換するか、別途 `flutter build apk --release` を実行する。
- AAB・APK・keystore・`key.properties` は**絶対にコミットしない**（`.gitignore` 済み前提だが `git status` で確認する）。配布は人間が行う。

## 7. コミットとリリース PR

コミット（変更は `CHANGELOG.md` と `pubspec.yaml` の 2 ファイルのみ）:

```
chore: リリース vX.Y.Z 準備（バージョン更新・CHANGELOG 記載）

FR-7: pubspec.yaml を A.B.C+N → X.Y.Z+M に更新し、CHANGELOG の
[Unreleased] を [X.Y.Z] - YYYY-MM-DD にリネーム。<主な変更の要約>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

push 後、`gh pr create --base main --head release/x.y.z --title "release: vX.Y.Z"` で PR を作る。本文は以下の構成（PR #85 に準拠）:

```markdown
## 概要
develop → main のリリース PR（vX.Y.Z）。前回リリース `A.B.C` 以降の新機能・修正をまとめて本番へ反映する。

- `pubspec.yaml`: `A.B.C+N` → `X.Y.Z+M`
- `CHANGELOG.md`: `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` にリネームし、新しい空の `[Unreleased]` を追加（FR-7）

main への push を検知して CI（`publish-release-version.yml`）が CHANGELOG から `[X.Y.Z]` を読み取り、Firestore `meta/release` に反映する。

## 含まれる変更（A.B.C 以降）
- <変更の要約> (#issue)

## リリースノート（利用者向け / CHANGELOG [X.Y.Z]）
- <CHANGELOG の該当セクションをそのまま転記>

## 検証
- [x] `flutter analyze`（警告ゼロ）
- [x] `flutter test`
- [x] `flutter build appbundle --release`（リリース署名鍵で署名）
- [ ] マージ後、`meta/release` が `version=X.Y.Z` に更新されることを確認

> 注: マージ後、本 PR のバージョン更新コミットを develop にも反映（back-merge）してバージョンずれを解消すること。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 8. 完了報告

ユーザーに次を伝える:

- 新バージョンと PR の URL
- 実行した検証コマンドとその結果
- ビルドした AAB のパス
- 残っている人間の作業: PR レビューとマージ → CI（`meta/release` / Pages）の確認 → AAB を配布経路（Play Console 等）に上げて家族に届ける → `main` を `develop` に back-merge。
  手順とコマンドは [docs/運用/リリース手順.md](../../../docs/運用/リリース手順.md) の 2〜5 章にあるので、その参照を必ず添える（back-merge を忘れると develop のバージョンがずれる）。

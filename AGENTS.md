# AGENTS.md — KanSuke コーディングエージェント向けガイド

> このファイルは Codex CLI / その他コーディングエージェントが**起動時に自動で読む**リポジトリ文脈です。
> Issue を実装する前に必ず本書と関連ドキュメントを読んでから着手してください。

## プロジェクト概要

**KanSuke** は家庭内専用のスケジュール共有アプリ（TimeTree の代替）。一般公開・ストア配信は行わず、家族数名のクローズド運用に限定する。

- 「誰の予定か」を色で一目判別
- 「仮の予定」と「確定予定」を区別
- iPhone（iOS 16）でストレスなく操作できること

詳細な仕様は必ず以下を参照すること（**仕様の正典**）：

- 要件定義: [docs/要件定義.md](docs/要件定義.md)
- 基本設計: [docs/基本設計.md](docs/基本設計.md)
- 要求メモ: [docs/要求メモ.md](docs/要求メモ.md)

## 技術スタック

| 層 | 採用技術 |
| --- | --- |
| クライアント | Flutter（iOS 16+ / Android）、状態管理 **Riverpod**、月表示 **table_calendar** |
| 認証 | Firebase Authentication（`google_sign_in` / `sign_in_with_apple`） |
| DB | Cloud Firestore（オフライン永続化・リアルタイム同期） |
| アクセス制御 | Firestore Security Rules（カレンダー参加者チェック）+ Auth Blocking Function（アカウント作成時の初期化） |
| 通知 | Cloud Functions for Firebase + FCM（`firebase_messaging`） |
| 実行基盤 | Firebase（Blaze プラン） |

## ディレクトリ構成（想定）

```
docs/        # 仕様書（正典。実装前に必読）
lib/         # Flutter アプリ本体（feature 単位で分割）
test/        # Flutter テスト
functions/   # Cloud Functions（リマインド等）
firestore.rules / firestore.indexes.json / firebase.json  # Firebase 構成
```

> 注: 現時点ではまだ Flutter プロジェクトは未初期化。最初の Issue でscaffoldする。

## ビルド・検証コマンド

> Flutter プロジェクト初期化後に有効。**変更を加えたら必ずローカルで通すこと。**

```bash
flutter pub get        # 依存取得
flutter analyze        # 静的解析（警告ゼロを維持）
dart format .          # フォーマット
flutter test           # ユニット/ウィジェットテスト
```

Cloud Functions 側（`functions/`）:

```bash
npm --prefix functions ci
npm --prefix functions run lint
npm --prefix functions test
```

## コーディング規約

- **言語**: コメント・ドキュメント・コミットメッセージは日本語可。コード識別子は英語。
- **状態管理は Riverpod** を使う。グローバルな可変状態・シングルトンを避ける。
- **オフラインファースト**: 表示は常に Firestore ローカルキャッシュ起点で組む。
- Firestore のドキュメント ID は**クライアント生成 UUID**（オフライン作成で安定させるため）。
- `flutter analyze` の警告ゼロ、`dart format` 済みを維持。
- 仕様（FR-x / NFR-x）に対応する実装には、コメントや PR 本文で対応番号を明記する。

## エージェント作業ルール（重要）

1. **Issue 単位で完結**させる。1 Issue = 1 ブランチ = 1 PR。
2. **ブランチ名**: `feat/<issue番号>-<短い英語スラッグ>`（例 `feat/12-event-crud`）。修正系は `fix/`。
3. **作業前に対象 Issue の「受け入れ条件」を満たす計画**を立て、スコープ外には手を出さない。
4. **`docs/` の仕様書は勝手に書き換えない**。仕様変更が必要だと判断したら、実装せず Issue にコメント/質問として残す。
5. **秘密情報をコミットしない**: `google-services.json` / `GoogleService-Info.plist` / `.firebaserc` の本番値 / APNs 鍵 / `*.keystore` 等は `.gitignore` 済み前提で扱う。
6. PR 本文には「対応 Issue 番号」「対応した受け入れ条件のチェック」「実行した検証コマンドと結果」を必ず書く。
7. 判断に迷う点・仕様の欠落は、推測で実装せず Issue に質問として明記する。

## コミット / PR 規約

- コミットは小さく、論理単位で。プレフィックス例: `feat:` `fix:` `docs:` `chore:` `test:`。
- PR タイトル: `feat: 予定のCRUD実装 (#12)` のように Issue 番号を含める。
- PR は `develop` 向け。マージ前に `flutter analyze` / `flutter test` がローカルで通っていること。

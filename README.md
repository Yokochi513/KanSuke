# KanSuke

## Firebase のローカル設定

このリポジトリの Firebase 構成値はプレースホルダーです。実機または
エミュレーターで起動する前に、対象の Firebase プロジェクトへログインし、
リポジトリのルートで次を実行してください。

```bash
firebase use <project-id>
flutterfire configure --project=<project-id> --platforms=android,ios
flutter run
```

起動時に `Firebase.initializeApp()` が完了して KanSuke のホーム画面が表示されれば、
初期化成功です。生成される `lib/firebase_options.dart` と `.firebaserc` の差分には
プロジェクト固有値が含まれるため、そのままコミットしないでください。

`google-services.json`、`GoogleService-Info.plist`、APNs 鍵などの秘密ファイルは
`.gitignore` の対象です。

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
## Cloud Functions

`functions/` は Cloud Functions（Node.js）と Firestore ルールテストを含みます。

```bash
npm --prefix functions ci
npm --prefix functions run lint
npm --prefix functions test        # Functions のユニットテスト（エミュレータ不要）
npm --prefix functions run test:rules  # Firestore ルールテスト（エミュレータ＋JDK21+ が必要）
```

`beforefamilymembercreated`（`beforeUserCreated` Blocking Function）は、
サインアップ時にメールを `allowlist/{email}` と照合し、対象外を拒否します。
許可ユーザーの初回サインアップ時に `users/{uid}` を allowlist 情報（name / color）
から生成します（基本設計 §2.1）。

### 家族 allowlist の投入（管理者用）

新しい家族メンバーを追加するには、管理者が `allowlist/{email}` を登録します。

```bash
# 管理者権限のサービスアカウント鍵と対象プロジェクトを指定
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
export GOOGLE_CLOUD_PROJECT=<firebase-project-id>

node functions/scripts/set-allowlist.js <email> <name> "<#RRGGBB>"
# 例: node functions/scripts/set-allowlist.js mom@example.com ママ "#D84315"
```

### デプロイ

```bash
firebase deploy --only functions --project <project-id>
firebase deploy --only firestore:rules,firestore:indexes --dry-run --project <project-id>
```

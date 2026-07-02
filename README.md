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
## Firestore 構成の検証

ルールテストは Firestore エミュレータを自動起動して実行します。

```bash
npm --prefix functions ci
npm --prefix functions run lint
npm --prefix functions test
```

デプロイ前は対象の Firebase プロジェクトを指定し、Rules とインデックスの
dry-run を実行します。

```bash
firebase deploy --only firestore:rules,firestore:indexes --dry-run --project <project-id>
```

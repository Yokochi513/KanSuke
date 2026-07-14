# KanSuke

## Firebase のローカル設定

このリポジトリの Firebase 構成値はプレースホルダーです。実機または
エミュレーターで起動する前に、対象の Firebase プロジェクトへログインし、
リポジトリのルートで次を実行してください。

```bash
firebase use <project-id>
flutterfire configure --project=<project-id> --platforms=android,ios,web
flutter run                 # 実機/エミュレーター
flutter run -d chrome       # Web（ブラウザ）
```

起動時に `Firebase.initializeApp()` が完了して KanSuke のホーム画面が表示されれば、
初期化成功です。

### 設定ファイルのコミット方針

`lib/firebase_options.dart` / `firebase.json` / `android/**/build.gradle.kts` などに
含まれる Firebase の apiKey・appId・projectId は、クライアントに埋め込んで公開する
前提の設定値（真の秘密ではなく、アクセス制御は Firestore ルール＝カレンダーの参加者
チェックが担う）です。ビルド・起動に必須のため、**実値のままコミットします**。

一方 `.firebaserc` は Firebase CLI（`deploy` / `use`）専用でアプリは実行時に読まないため、
リポジトリにはプレースホルダー値を残し、実プロジェクト ID はローカルにのみ置きます。
別マシンで clone したら、そのマシンで一度だけ次を実行してください。

```bash
git update-index --skip-worktree .firebaserc   # 以後 .firebaserc のローカル変更を追跡しない
# その後 .firebaserc の "default" を対象の project-id に書き換える
```

これで `firebase` CLI はローカルの実プロジェクトを解決しつつ、リポジトリ側は
プレースホルダーのまま保たれます（差分がコミットに紛れ込みません）。

### 対応プラットフォーム

iOS / Android / Web に対応しています（`web/` は `flutter create` で構成済み）。
Web は `lib/firebase_options.dart` の `web` 設定を使用し、Firestore の
オフライン永続化は IndexedDB による単一タブ永続化として有効化されます（NFR-3）。

Web で Google サインインを本実装する際は、OAuth Web クライアント ID を
`web/index.html` の meta タグに設定する必要があります（詳細は同ファイルの
コメント参照）。`sign_in_with_apple` の Apple ボタンは iOS 実機のみ表示され、
Web では非表示です。

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
アカウント作成時に `users/{uid}`（表示名・メール・識別色）と、本人だけが参加する
個人カレンダーを生成します（基本設計 §2.1、FR-8）。サインアップ自体は制限しません。

### 家族の追加

相手にサインアップしてもらい、共有したいカレンダーの「参加者」に追加します
（カレンダー管理画面）。サインアップしただけの状態では、その人には自分の個人
カレンダーしか見えません。

### デプロイ

```bash
firebase deploy --only firestore:rules,firestore:indexes --dry-run --project <project-id>
firebase deploy --only firestore:rules,firestore:indexes --project <project-id>
firebase deploy --only functions --project <project-id>
```

初回のみ必要な作業（Cloud Scheduler の有効化・APNs 鍵の登録）やデプロイ後の確認方法は
[docs/運用/Firebaseデプロイ手順.md](docs/運用/Firebaseデプロイ手順.md) にまとめています。
アプリ（APK / Web）の配布は [docs/運用/リリース手順.md](docs/運用/リリース手順.md) を参照。

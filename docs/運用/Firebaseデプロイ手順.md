# Firebase デプロイ手順（Functions / Rules / インデックス）

> バックエンド側（Cloud Functions・Firestore Security Rules・複合インデックス）を
> Firebase に反映する手順。**アプリ（APK / iOS / Web）の配布は対象外**で、そちらは
> [リリース手順.md](リリース手順.md) を参照。
>
> アプリのリリース（`develop` → `main`）とバックエンドのデプロイは**別の作業**。
> `functions/` `firestore.rules` `firestore.indexes.json` を変更した PR をマージしても
> 自動デプロイはされないため、**マージ後に手動で本書の手順を実行する**必要がある。

## 前提

- Firebase CLI にログイン済み（`firebase login`）
- `.firebaserc` にローカルの実プロジェクト ID が入っている（[README](../../README.md) 参照）
- Blaze プラン（Functions / Cloud Scheduler の利用に必須）

## デプロイ手順

`<project-id>` は実プロジェクト ID（`.firebaserc` の `default`）に読み替える。

### 1. 事前チェック（ローカル）

```bash
npm --prefix functions ci
npm --prefix functions run lint
npm --prefix functions test
```

### 2. Rules / インデックスを dry-run で確認

```bash
firebase deploy --only firestore:rules,firestore:indexes --dry-run --project <project-id>
```

### 3. デプロイ

```bash
firebase deploy --only firestore:rules,firestore:indexes --project <project-id>
firebase deploy --only functions --project <project-id>
```

**インデックスを Functions より先に**デプロイする。インデックスの作成はデータ量に応じて
数分かかることがあり、未完成のまま Function が動くとクエリが失敗するため。
作成状況は Firebase Console →  Firestore → インデックス で確認できる。

## 現在デプロイされるもの

### Cloud Functions（リージョン `asia-northeast1`）

| 関数名 | トリガ | 役割 |
| --- | --- | --- |
| `beforefamilymembercreated` | Auth Blocking（作成前） | `users/{uid}` と個人カレンダーを生成（FR-8、基本設計 §2.1） |
| `removemember` / `leavecalendar` / `transferownership` | onCall | カレンダーの権限操作（Issue #89） |
| `createinvite` / `previewinvite` / `acceptinvite` / `revokeinvite` / `listinvites` | onCall | 招待リンク（FR-9、Issue #90） |
| `oneventwrite` | Firestore `events/{id}` onWrite | `reminders` の再生成（FR-5、Issue #14） |
| `sendduereminders` | スケジュール（毎分） | 配信時刻が来た `reminders` を FCM 送信（FR-5、Issue #14） |

> 関数名が小文字なのは Functions 2nd gen の命名制約による。仕様上の名前は
> `onEventWrite` / `sendDueReminders`（基本設計 §5.1）。

### Firestore 複合インデックス

| コレクション | フィールド | 用途 |
| --- | --- | --- |
| `calendars` | — | カレンダー一覧 |
| `events` | — | 予定の期間クエリ |
| `reminders` | `sent`, `triggerAt`（昇順） | `sendduereminders` の due 抽出（Issue #14） |

## 初回のみ必要になる作業（人間・Console 操作）

一度実施すれば以後は不要。**Firebase Console 側の設定はエージェントに代行させず、
本人が実施する**（過去の運用方針）。

### Cloud Scheduler の有効化（リマインド、Issue #14）

`sendduereminders` は毎分実行のスケジュール関数で、内部的に Cloud Scheduler と
Pub/Sub を使う。初回デプロイ時に API の有効化を求められた場合は、CLI の指示に従うか
Google Cloud Console で `cloudscheduler.googleapis.com` / `pubsub.googleapis.com` を
有効化してからデプロイし直す。

有効化後、Google Cloud Console → Cloud Scheduler に毎分実行のジョブが1件現れる。

### APNs 認証鍵の登録（iOS の通知、FR-5）

iOS 実機にプッシュ通知を届けるには、Apple Developer で作成した APNs 認証鍵（`.p8`）を
Firebase Console → プロジェクトの設定 → Cloud Messaging に登録する必要がある。
未登録だと Android / Web には届くが iOS だけ届かない。

- `.p8` 鍵・Key ID・Team ID は**コミットしない**
- 詳細は [iOSデプロイ手順.md](iOSデプロイ手順.md) を参照

## デプロイ後の確認

```bash
firebase functions:list --project <project-id>          # 関数が並ぶこと
firebase functions:log --only sendduereminders --project <project-id>
```

リマインド（Issue #14）の動作確認:

1. アプリで数分後に始まる予定を作り、自分に「n 分前」のリマインドを設定する
2. Firestore の `reminders` に `ownerId` = 自分の uid、`triggerAt` = `startAt - n分`、
   `sent: false` のドキュメントが生成される（`oneventwrite`）
3. `triggerAt` を過ぎた次の実行で端末に通知が届き、`sent: true` になる（`sendduereminders`）

通知が届かない場合の切り分け:

| 症状 | 見るところ |
| --- | --- |
| `reminders` が生成されない | `oneventwrite` のログ。予定の `reminderOffsets` が `{uid: [分]}` 形式か（旧 `number[]` は「設定なし」として無視される） |
| `reminders` は出るが `sent` のままにならない | Cloud Scheduler のジョブが動いているか。`sendduereminders` のログ |
| `sent: true` になるのに通知が来ない | `users/{uid}/devices` にトークンがあるか（Issue #13）。iOS なら APNs 鍵の登録 |
| 生成時点で既に過ぎている分 | 仕様通り生成しない（過去の予定を即通知しないため。基本設計 §3.2） |

## チェックリスト

- [ ] `npm --prefix functions run lint && npm --prefix functions test` が通った
- [ ] Rules / インデックスを dry-run で確認した
- [ ] インデックス → Functions の順にデプロイした
- [ ] （初回のみ）Cloud Scheduler の API を有効化した
- [ ] （初回のみ）APNs 認証鍵を Firebase Console に登録した
- [ ] `firebase functions:list` に想定の関数が並んだ

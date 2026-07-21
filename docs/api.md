# KanSuke 外部向け REST API v1（読み取り専用）

自分用スクリプト（GAS・Home Assistant など）、他カレンダーへのエクスポート、AI アシスタント連携
（MCP サーバー等）から KanSuke の予定を参照するための HTTP API。**利用者は KanSuke のユーザー本人に
限られる**ため、認証は既存のサインインで得られる Firebase ID トークンをそのまま使う（API キー発行や
OAuth2 は行わない）。

対応 Issue: #103 / 対応要件: FR-1・FR-3・FR-8

## 基本情報

| 項目 | 内容 |
| --- | --- |
| ベース URL | `https://api.dreamyard.cc` |
| メソッド | **`GET` のみ**（v1 は読み取り専用。書き込みは未実装） |
| 認証 | `Authorization: Bearer <Firebase ID トークン>` |
| 形式 | リクエスト・レスポンスとも JSON（UTF-8） |
| 時刻 | すべて ISO 8601（UTC）。例 `2026-07-14T09:00:00Z` |
| CORS | 許可オリジンのみ（環境変数 `API_ALLOWED_ORIGINS`、既定は Web 版の配信元 `https://yokochi513.github.io`）。curl 等は Origin を送らないため影響を受けない |
| レートリミット | uid 単位で 120 リクエスト / 分（インスタンス内のベストエフォート。超過は 429） |

### 配信経路

公開する URL は Cloudflare Worker（`cloudflare/api-proxy/`）の 1 つだけ。実体の Cloud
Functions（`*.cloudfunctions.net`）は表に出さない。

```
クライアント ──► https://api.dreamyard.cc/v1/...    Cloudflare Worker
                                │  X-Api-Proxy-Key を付与
                                ▼
                          Cloud Functions（api）
                          鍵が一致しなければ 404
```

Worker は共有シークレット `API_PROXY_KEY` をヘッダで付与し、Functions 側は一致しない
リクエストを **404** で落とす。したがって Cloud Functions の URL を知られても、そこを直接
叩く経路は使えない（URL を隠すだけの対策では終わらせていない）。

### アクセス制御（重要）

この API は Admin SDK で Firestore を読むため **Security Rules を経由しない**。代わりに
「呼び出し元 uid が対象カレンダーの `memberIds` に含まれること」を API 側で全ハンドラ共通に検証する
（`functions/api/router.js` の `requireCalendarMembership()`）。自分がメンバーでないカレンダー ID /
予定 ID を指定した場合は、**存在しない場合と区別せず 404** を返す（存在の有無も漏らさない）。

## ID トークンの取得

ID トークンは**発行から 1 時間で失効**する。長く動かすスクリプトはリフレッシュトークンから
取り直すこと。

### A. 手元で curl を試すとき（Web 版のコンソールから取得）

Web 版で Google サインインした状態で、ブラウザの DevTools コンソールで以下を実行する。

```js
await firebase.auth().currentUser.getIdToken()
```

出力された文字列をそのまま `Authorization: Bearer ...` に使う。

### B. スクリプトから継続的に使うとき（カスタムトークン経由）

1. Firebase コンソール → プロジェクトの設定 → サービスアカウントから秘密鍵（JSON）を発行する。
   **この鍵はコミットしない**（`.gitignore` 済みの場所か、リポジトリ外に置く）。
2. Admin SDK で自分の uid のカスタムトークンを作る。

   ```js
   const admin = require("firebase-admin");
   admin.initializeApp({credential: admin.credential.cert(require("./service-account.json"))});
   admin.auth().createCustomToken("<自分の uid>").then(console.log);
   ```

3. カスタムトークンを ID トークン＋リフレッシュトークンに交換する（`<WEB_API_KEY>` は
   Firebase コンソールのウェブ API キー）。

   ```bash
   curl -s -X POST \
     "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=<WEB_API_KEY>" \
     -H "Content-Type: application/json" \
     -d '{"token":"<カスタムトークン>","returnSecureToken":true}'
   # => {"idToken":"...","refreshToken":"...","expiresIn":"3600"}
   ```

4. 以後は失効前にリフレッシュトークンから取り直す。

   ```bash
   curl -s -X POST "https://securetoken.googleapis.com/v1/token?key=<WEB_API_KEY>" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=refresh_token&refresh_token=<リフレッシュトークン>"
   ```

## エンドポイント

以下、`TOKEN` に ID トークン、`BASE` にベース URL が入っているものとする。

```bash
export BASE="https://api.dreamyard.cc"
export TOKEN="<Firebase ID トークン>"
```

### `GET /v1/me`

自分のプロフィール。

```bash
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/v1/me"
```

```json
{
  "uid": "AbC123...",
  "name": "パパ",
  "color": "#FF7043"
}
```

### `GET /v1/calendars`

自分が参加しているカレンダー一覧（名前の昇順）。参加していないカレンダーは含まれない。

```bash
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/v1/calendars"
```

```json
{
  "calendars": [
    {
      "id": "0f0e6e4c-...",
      "name": "わが家",
      "ownerId": "AbC123...",
      "memberIds": ["AbC123...", "XyZ789..."]
    }
  ]
}
```

### `GET /v1/calendars/{calendarId}`

カレンダー詳細。メンバーでなければ 404。レスポンスは `calendars` の要素と同じ形。

```bash
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/v1/calendars/0f0e6e4c-..."
```

### `GET /v1/events`

予定一覧。開始日時（`startAt`）が `from` 以上 `to` 未満の予定を、開始日時の昇順で返す。

| クエリ | 必須 | 説明 |
| --- | --- | --- |
| `calendarId` | ✅ | 対象カレンダー。メンバーでなければ 404 |
| `from` | ✅ | 期間の開始（ISO 8601。この時刻を含む） |
| `to` | ✅ | 期間の終了（ISO 8601。この時刻を含まない） |
| `limit` | | 1 ページの件数。既定 100・上限 500 |
| `cursor` | | 前ページのレスポンスの `nextCursor`（不透明な文字列） |

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/v1/events?calendarId=0f0e6e4c-...&from=2026-07-01T00:00:00Z&to=2026-08-01T00:00:00Z"
```

```json
{
  "events": [
    {
      "id": "8b2f1a90-...",
      "calendarId": "0f0e6e4c-...",
      "title": "歯医者",
      "creatorId": "AbC123...",
      "participantIds": ["AbC123..."],
      "startAt": "2026-07-14T09:00:00Z",
      "endAt": "2026-07-14T10:00:00Z",
      "allDay": false,
      "type": "confirmed",
      "memo": "",
      "reminderOffsets": {"AbC123...": [60]},
      "recurrenceFrequency": null,
      "recurrenceCount": null,
      "createdAt": "2026-07-01T02:11:43Z",
      "updatedAt": "2026-07-01T02:11:43Z"
    }
  ],
  "nextCursor": null
}
```

- 削除済み（`deleted == true`）の予定は返さない。内部の監査フィールド `deleted` / `updatedBy` も
  レスポンスに含めない。
- **繰り返し予定は展開しない**。マスタのドキュメントを 1 件として返し、繰り返しの規則は
  `recurrenceFrequency`（`weekly` / `monthly` / `yearly`）と `recurrenceCount` で表す。
  発生日単位の列挙や ICS 配信は後続 Issue（v1 のスコープ外）。
- 期間の判定は**開始日時**のみで行う。`from` より前に始まって期間内まで続く長い予定は含まれない
  （アプリの月表示と同じ絞り込み）。

#### ページング

`nextCursor` が `null` 以外なら次ページがある。同じ `calendarId` / `from` / `to` のまま `cursor` に
渡して繰り返す。

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/v1/events?calendarId=$CAL&from=$FROM&to=$TO&limit=100&cursor=$NEXT"
```

### `GET /v1/events/{eventId}`

予定 1 件。所属カレンダーのメンバーでなければ 404。削除済みの予定も 404。

```bash
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/v1/events/8b2f1a90-..."
```

## エラー

エラーは常に次の形で返る。

```json
{"error": {"code": "unauthenticated", "message": "ID トークンが無効です。"}}
```

| HTTP | `code` | 主な原因 |
| --- | --- | --- |
| 400 | `invalid_argument` | 必須クエリの欠落、日時・`limit`・`cursor` の不正、`GET` 以外のメソッド |
| 401 | `unauthenticated` | `Authorization` ヘッダの欠落、トークンが不正・期限切れ |
| 403 | `permission_denied` | （v1 では未使用。権限不足は 404 に寄せている） |
| 404 | `not_found` | 未知のパス、存在しない／自分がメンバーでないカレンダー・予定 |
| 429 | `resource_exhausted` | レートリミット超過 |
| 500 | `internal` | サーバー側の予期しないエラー |

## 実装

| ファイル | 役割 |
| --- | --- |
| `functions/index.js` | `exports.api`（Cloud Functions v2 `onRequest`） |
| `functions/api/index.js` | CORS・ID トークン検証・レートリミット・レスポンス整形 |
| `functions/api/router.js` | パスのルーティングと各ハンドラ、**メンバーシップ検証** |
| `functions/api/serialize.js` | Firestore ドキュメント → JSON（ISO 8601 変換） |
| `functions/api/ratelimit.js` | uid 単位の簡易レートリミット |
| `functions/api/errors.js` | エラーコードと HTTP ステータスの対応 |
| `functions/test/api.test.js` | ユニットテスト |
| `cloudflare/api-proxy/` | 公開 URL の Worker（リバースプロキシ＋共有シークレット付与） |
| `docs-site/` | このページ（`docs/api.md` → HTML）の Cloudflare Pages ビルド |

`events` の期間クエリは既存の複合インデックス `(deleted, calendarId, startAt)`
（`firestore.indexes.json`）をそのまま使うため、インデックスの追加は不要。

### デプロイ

```bash
# 1. 共有シークレットを両側に同じ値で設定（初回のみ）
openssl rand -base64 48
firebase functions:secrets:set API_PROXY_KEY
cd cloudflare/api-proxy && npx wrangler secret put API_PROXY_KEY

# 2. Functions
firebase deploy --only functions:api

# 3. Cloudflare Worker
cd cloudflare/api-proxy && npx wrangler deploy
```

ドキュメントページ（Cloudflare Pages）は `main` への push で自動ビルドされる。
詳細は `cloudflare/api-proxy/README.md` と `docs-site/README.md` を参照。

## v1 のスコープ外

- **書き込み API**（予定の作成・更新・削除、カレンダー管理）
- **ICS（iCalendar）配信**。Google カレンダー等の購読クライアントは `Authorization` ヘッダを
  送れないため、署名付き URL の読み取り専用エンドポイントが別途必要。繰り返し予定の展開とセットで
  別 Issue とする。

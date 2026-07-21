# kansuke-api-proxy（Cloudflare Worker）

外部向け REST API（Issue #103）の公開 URL を `https://api.<ドメイン>` に一本化する
リバースプロキシ。実体の `*.cloudfunctions.net` URL とプロジェクト ID を表に出さず、
かつ共有シークレットで直アクセスを塞ぐ。

```
クライアント ──► https://api.<ドメイン>/v1/events
                     │  Cloudflare Worker
                     │  X-Api-Proxy-Key を付与
                     ▼
                  https://asia-northeast1-....cloudfunctions.net/api/v1/events
                     （鍵が一致しないリクエストは 404）
```

## セットアップ

### 1. ドメインを設定する

`wrangler.toml` の `routes` を自分のドメインに書き換える。**置き換えるのはここだけ。**

```toml
routes = [
  { pattern = "api.example.com/*", zone_name = "example.com" }
]
```

ゾーン（ドメイン）が Cloudflare に登録済みであること。`api` の DNS レコードは
Worker のルートが引き受けるため、プロキシ済み（オレンジ雲）の A レコード
`192.0.2.1`（ダミー）または AAAA `100::` を 1 本置いておく。

### 2. 共有シークレットを作る

十分に長いランダム文字列を 1 つ生成し、**Worker と Functions の両方に同じ値**を入れる。

```bash
# 生成（例）
openssl rand -base64 48

# Cloudflare 側
npx wrangler secret put API_PROXY_KEY

# Firebase 側（Secret Manager）
firebase functions:secrets:set API_PROXY_KEY
```

> Functions 側は `API_PROXY_KEY` が未設定なら検証をスキップする（エミュレータ用）。
> 本番にデプロイしたら**必ず設定する**。設定前は直アクセスが素通りする。

### 3. デプロイ

```bash
cd cloudflare/api-proxy
npx wrangler deploy

# Functions 側にも鍵を反映するため、あわせて再デプロイ
firebase deploy --only functions:api
```

### 4. 疎通確認

```bash
# プロキシ経由（正常）
curl -s -H "Authorization: Bearer $TOKEN" https://api.example.com/v1/me

# 直アクセス（404 になること）
curl -s -o /dev/null -w '%{http_code}\n' \
  https://asia-northeast1-kansuke-b6d32.cloudfunctions.net/api/v1/me
# => 404
```

## ローカル開発

```bash
cd cloudflare/api-proxy
echo 'API_PROXY_KEY="<鍵>"' > .dev.vars   # .gitignore 済み
npx wrangler dev
```

## 設計メモ

- 転送するリクエストヘッダは `Authorization` と CORS のプリフライト関連のみ。
  Cookie・User-Agent は上流に渡さない。
- レスポンスは許可したヘッダだけを組み直して返し、上流の `server` やトレース ID を
  漏らさない。
- CORS の判定は Functions 側（`functions/api/index.js`）が行う。Worker は
  `Origin` をそのまま転送するだけ。許可オリジンの変更は Functions の環境変数
  `API_ALLOWED_ORIGINS` で行う。
- `GET` / `OPTIONS` 以外は Worker の時点で 400 にして上流に届かせない。

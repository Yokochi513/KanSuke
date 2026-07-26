# kansuke-api-docs（Cloudflare Pages）

`docs/api.md` を静的な HTML 1 枚にして公開するためのビルド。**仕様の正本は
`docs/api.md`** で、こちらは体裁を付けるだけ。ドキュメントの修正は Markdown 側で行う。

## ローカルで確認する

```bash
cd docs-site
npm install
npm run build
# dist/index.html をブラウザで開く
```

`dist/` は生成物なのでコミットしない（`.gitignore` 済み）。

## Cloudflare Pages の設定

Cloudflare ダッシュボード → Workers & Pages → Create → Pages → Connect to Git で
`Yokochi513/KanSuke` を選び、以下を設定する。GitHub Actions は不要
（Pages が push を検知してビルドする）。

| 項目 | 値 |
| --- | --- |
| Production branch | `main` |
| Root directory | `docs-site` |
| Build command | `npm run build` |
| Build output directory | `dist` |

デプロイ後、Custom domains から `docs.dreamyard.cc` を割り当てる。

## 公開範囲

このページは公開（誰でも閲覧可）。API 自体は Firebase ID トークンが無ければ何も
返さないため、仕様が読まれても予定は露出しない。閲覧者を絞りたくなったら
Cloudflare Zero Trust の Access ポリシーを後から被せられる。

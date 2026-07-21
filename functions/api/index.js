"use strict";

// 外部向け読み取り専用 REST API の HTTP 入口（Issue #103）。
//
// Cloud Functions v2 の `onRequest` 1 関数（`api`）にまとめ、パスでルーティング
// する。責務はこの順で:
//   1. CORS（許可オリジンのみ。プリフライトはここで返す）
//   2. Firebase ID トークンの検証（欠落・不正・期限切れは 401）
//   3. uid 単位の簡易レートリミット（超過は 429）
//   4. ルータ（`router.js`）へ委譲
//
// 認可（カレンダーのメンバーシップ検証）は router 側の共通関門で行う。
// Admin SDK で読むため Security Rules は効かない点に注意（router.js 冒頭参照）。

const {timingSafeEqual} = require("node:crypto");

const {ApiError, notFound} = require("./errors");
const {createRateLimiter} = require("./ratelimit");
const {handleApiRequest} = require("./router");

// 既定の許可オリジン（Web 版の配信元）。Web 版は GitHub Pages で配信している
// （.github/workflows/deploy-pages.yml）。環境変数 `API_ALLOWED_ORIGINS`
// （カンマ区切り）で上書きできる。curl 等の非ブラウザクライアントは Origin を
// 送らないため、この設定に影響されない。
const DEFAULT_ALLOWED_ORIGINS = ["https://yokochi513.github.io"];

/**
 * 環境変数から許可オリジンを読む。
 *
 * @param {object} env `process.env` 相当。
 * @return {string[]}
 */
function allowedOriginsFrom(env) {
  const raw = env && env.API_ALLOWED_ORIGINS;
  if (typeof raw !== "string" || raw.trim() === "") {
    return DEFAULT_ALLOWED_ORIGINS;
  }
  return raw
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin !== "");
}

/**
 * `Authorization: Bearer <ID トークン>` からトークンを取り出す。
 *
 * @param {*} header ヘッダの値。
 * @return {string} ID トークン。
 */
function bearerTokenOf(header) {
  const match = /^Bearer (.+)$/.exec(String(header || "").trim());
  if (!match) {
    throw new ApiError(
      "unauthenticated",
      "Authorization: Bearer <Firebase ID トークン> が必要です。",
    );
  }
  return match[1];
}

/**
 * ID トークンを検証して uid を得る。失効・改ざん・期限切れはすべて 401。
 *
 * @param {object} auth Firebase Admin の Auth。
 * @param {string} idToken ID トークン。
 * @return {Promise<string>} uid。
 */
async function verifyUid(auth, idToken) {
  try {
    const decoded = await auth.verifyIdToken(idToken);
    return decoded.uid;
  } catch (error) {
    throw new ApiError("unauthenticated", "ID トークンが無効です。");
  }
}

/**
 * Cloudflare Worker が付与する共有シークレットを検証する（プロキシ経由の強制）。
 *
 * 公開 URL は `https://api.dreamyard.cc`（Cloudflare Worker）に一本化し、素の
 * `*.cloudfunctions.net` を直接叩く経路を塞ぐための関門。鍵が一致しない場合は
 * **401/403 ではなく 404** を返す。「鍵が違う」と答えると、この URL に API が
 * 存在すること自体を教えてしまうため。
 *
 * `API_PROXY_KEY` 未設定時は検証しない（エミュレータ・ローカルテスト用）。
 *
 * @param {*} expected 期待する鍵（Secret Manager 由来）。
 * @param {*} actual リクエストヘッダの値。
 * @return {void}
 */
function verifyProxyKey(expected, actual) {
  if (typeof expected !== "string" || expected === "") return;
  const provided = Buffer.from(String(actual || ""), "utf8");
  const secret = Buffer.from(expected, "utf8");
  // timingSafeEqual は長さが違うと例外を投げるため、先に長さで弾く
  // （長さの一致だけは漏れるが、鍵の中身は総当たりできない）。
  if (provided.length !== secret.length) throw notFound();
  if (!timingSafeEqual(provided, secret)) throw notFound();
}

/**
 * HTTP ハンドラ（`onRequest` に渡す関数）を作る。
 *
 * @param {{db: object, auth: object, env?: object, now?: function(): Date,
 *   rateLimiter?: object}} deps 依存。
 * @return {function(object, object): Promise<void>}
 */
function createApiHandler(deps) {
  const {db, auth} = deps;
  const env = deps.env || process.env;
  const now = deps.now || (() => new Date());
  const rateLimiter = deps.rateLimiter || createRateLimiter();
  const allowedOrigins = allowedOriginsFrom(env);

  return async function apiHandler(req, res) {
    const origin = req.headers && req.headers.origin;
    if (origin && allowedOrigins.includes(origin)) {
      res.set("Access-Control-Allow-Origin", origin);
      res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
      res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
      res.set("Access-Control-Max-Age", "3600");
    }
    // 許可外オリジンには CORS ヘッダを付けない（ブラウザ側で遮断される）。
    res.set("Vary", "Origin");
    res.set("Cache-Control", "no-store");

    try {
      // 鍵の検証は認証より先に行う。プロキシを経由しないリクエストには、
      // トークンの有無にかかわらず何も返さない。
      // シークレットは実行時に注入されるため、毎回 env から読む。
      verifyProxyKey(
        env.API_PROXY_KEY,
        req.headers && req.headers["x-api-proxy-key"],
      );

      if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
      }

      const uid = await verifyUid(
        auth,
        bearerTokenOf(req.headers && req.headers.authorization),
      );
      rateLimiter.check(uid, now());
      const path = req.path || String(req.url || "").split("?")[0];
      const {status, body} = await handleApiRequest(
        {db},
        {method: req.method, path, query: req.query || {}, uid},
      );
      res.status(status).json(body);
    } catch (error) {
      if (error instanceof ApiError) {
        res.status(error.status).json({
          error: {code: error.code, message: error.message},
        });
        return;
      }
      console.error("api: 予期しないエラー", error);
      res.status(500).json({
        error: {code: "internal", message: "サーバーエラーが発生しました。"},
      });
    }
  };
}

module.exports = {
  DEFAULT_ALLOWED_ORIGINS,
  allowedOriginsFrom,
  bearerTokenOf,
  createApiHandler,
  verifyProxyKey,
};

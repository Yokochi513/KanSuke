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

const {ApiError} = require("./errors");
const {createRateLimiter} = require("./ratelimit");
const {handleApiRequest} = require("./router");

// 既定の許可オリジン（Web 版のホスティングドメイン）。環境変数
// `API_ALLOWED_ORIGINS`（カンマ区切り）で上書きできる。curl 等の
// 非ブラウザクライアントは Origin を送らないため、この設定に影響されない。
const DEFAULT_ALLOWED_ORIGINS = [
  "https://kansuke-b6d32.web.app",
  "https://kansuke-b6d32.firebaseapp.com",
];

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

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
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
};

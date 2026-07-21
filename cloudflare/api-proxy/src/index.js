// KanSuke 外部向け REST API のリバースプロキシ（Issue #103）。
//
// 公開する URL を `https://api.dreamyard.cc` に一本化し、実体である
// `*.cloudfunctions.net` の URL とプロジェクト ID を表に出さないためのもの。
//
// 単なる URL の付け替えではなく、共有シークレット `API_PROXY_KEY` を
// `X-Api-Proxy-Key` ヘッダで付与する。Functions 側（functions/api/index.js の
// verifyProxyKey）は鍵が一致しないリクエストを 404 で落とすため、この Worker を
// 経由しない直アクセスは実際に塞がる（隠蔽だけで終わらせない）。
//
// 転送するのは読み取りに必要な最小限のヘッダのみ。レスポンスも許可した
// ヘッダだけを組み直して返し、上流の素性（`server` / トレース ID 等）を漏らさない。

const ORIGIN = "https://asia-northeast1-kansuke-b6d32.cloudfunctions.net/api";

// 上流へ通すリクエストヘッダ。Cookie・User-Agent 等は転送しない。
const FORWARDED_REQUEST_HEADERS = [
  "authorization",
  "origin",
  "access-control-request-headers",
  "access-control-request-method",
];

// 呼び出し元へ返すレスポンスヘッダ。ここに無いものは捨てる。
const FORWARDED_RESPONSE_HEADERS = [
  "content-type",
  "cache-control",
  "vary",
  "access-control-allow-origin",
  "access-control-allow-headers",
  "access-control-allow-methods",
  "access-control-max-age",
];

/**
 * API と同じ形のエラーレスポンスを組み立てる。
 *
 * @param {number} status HTTP ステータス。
 * @param {string} code エラーコード。
 * @param {string} message メッセージ。
 * @return {Response}
 */
function errorResponse(status, code, message) {
  return new Response(JSON.stringify({error: {code, message}}), {
    status,
    headers: {"content-type": "application/json; charset=utf-8"},
  });
}

export default {
  /**
   * @param {Request} request 受信リクエスト。
   * @param {{API_PROXY_KEY: string}} env Worker のシークレット。
   * @return {Promise<Response>}
   */
  async fetch(request, env) {
    // v1 は読み取り専用。書き込み系のメソッドは上流に届かせない。
    if (request.method !== "GET" && request.method !== "OPTIONS") {
      return errorResponse(
        400,
        "invalid_argument",
        "GET のみ対応しています。",
      );
    }

    if (!env.API_PROXY_KEY) {
      // 鍵未設定のまま公開すると、Functions 側の関門が無効な状態と組み合わさって
      // 直アクセスが素通りしうる。気づけるよう明示的に落とす。
      return errorResponse(
        500,
        "internal",
        "サーバー設定が不完全です。",
      );
    }

    const url = new URL(request.url);
    const target = new URL(ORIGIN + url.pathname + url.search);

    const headers = new Headers();
    for (const name of FORWARDED_REQUEST_HEADERS) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set("x-api-proxy-key", env.API_PROXY_KEY);

    let upstream;
    try {
      upstream = await fetch(target, {
        method: request.method,
        headers,
        redirect: "manual",
      });
    } catch (error) {
      return errorResponse(
        502,
        "internal",
        "サーバーに接続できませんでした。",
      );
    }

    const responseHeaders = new Headers();
    for (const name of FORWARDED_RESPONSE_HEADERS) {
      const value = upstream.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  },
};

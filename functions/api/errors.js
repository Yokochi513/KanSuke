"use strict";

// 外部向け読み取り専用 REST API のエラー表現（Issue #103）。
//
// レスポンス形は `{"error": {"code": "...", "message": "..."}}` に統一し、
// コードごとに HTTP ステータスを一意に決める。Callable の HttpsError とは
// 別系統（HTTP ステータスをそのまま返したいため）。

const STATUS_BY_CODE = {
  invalid_argument: 400,
  unauthenticated: 401,
  permission_denied: 403,
  not_found: 404,
  resource_exhausted: 429,
  internal: 500,
};

/** REST API のエラー。`code` が HTTP ステータスに対応する。 */
class ApiError extends Error {
  /**
   * @param {string} code `STATUS_BY_CODE` のキー。
   * @param {string} message 利用者向けメッセージ。
   */
  constructor(code, message) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.status = STATUS_BY_CODE[code] || 500;
  }
}

/**
 * 404 を返す（Issue #103）。
 *
 * 「存在しない」と「自分がメンバーでない」を**同じ 404 で区別なく**返すための
 * 共通ヘルパ。メッセージを分けると、他人のカレンダー ID / 予定 ID の存在有無が
 * 総当たりで判別できてしまうため、常にこの一種類だけを使う。
 *
 * @return {ApiError}
 */
function notFound() {
  return new ApiError("not_found", "見つかりません。");
}

/**
 * 引数エラーを返す。
 *
 * @param {string} message 利用者向けメッセージ。
 * @return {ApiError}
 */
function invalidArgument(message) {
  return new ApiError("invalid_argument", message);
}

module.exports = {ApiError, STATUS_BY_CODE, invalidArgument, notFound};

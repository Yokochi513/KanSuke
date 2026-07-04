"use strict";

// 家族 allowlist の照合ロジック（基本設計 §2.1）。
// Firestore/Functions に依存しない純粋関数にして単体テスト可能にする。

/**
 * サインアップ可否を判定する。
 *
 * @param {string} email 正規化済み（小文字）のサインインメール。
 * @param {?{name?: string, color?: string}} allowlistData
 *   `allowlist/{email}` の内容。存在しなければ null。
 * @return {{allowed: boolean, user?: {email: string,
 *   name: string, color: string}}}
 */
function evaluateSignup(email, allowlistData) {
  if (!email || !allowlistData) {
    return {allowed: false};
  }
  const name = typeof allowlistData.name === "string" ? allowlistData.name : "";
  const color =
    typeof allowlistData.color === "string" ? allowlistData.color : "";
  return {
    allowed: true,
    user: {email, name, color},
  };
}

module.exports = {evaluateSignup};

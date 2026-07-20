"use strict";

// FCM 送信まわりの共通ロジック（基本設計 §5.1・§5.2）。
//
// リマインド通知（Issue #14 / reminders.js）と予定変更の共有通知
// （Issue #77 / notifications.js）で共有する:
// - 配信先ユーザーの FCM トークン取得（`users/{uid}/devices/{token}`）
// - 送信結果からの無効トークン削除
// - Firestore Timestamp / Date / 文字列の Date 正規化
//
// Firestore / FCM を引数で受け取り、単体テスト可能にする。

/** FCM が「そのトークンはもう無効」と返すエラーコード（基本設計 §5.1）。 */
const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Firestore の Timestamp / Date / ISO 文字列を Date に正規化する。
 *
 * @param {*} value `startAt` などの時刻値。
 * @return {?Date} 変換できなければ null。
 */
function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * ユーザーの FCM トークン一覧（`users/{uid}/devices/{token}`、基本設計 §5.2）。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {string} uid 配信先ユーザー。
 * @return {Promise<string[]>} FCM トークン（= ドキュメント ID）。
 */
async function fetchTokens(db, uid) {
  const snapshot = await db.collection(`users/${uid}/devices`).get();
  return snapshot.docs.map((doc) => doc.id);
}

/**
 * 無効になったトークンの `devices` ドキュメントを削除する（基本設計 §5.1）。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {string} uid 配信先ユーザー。
 * @param {string[]} tokens 送信に使ったトークン（`responses` と同じ順序）。
 * @param {object[]} responses `sendEachForMulticast` の結果。
 * @return {Promise<string[]>} 削除したトークン。
 */
async function pruneInvalidTokens(db, uid, tokens, responses) {
  const invalid = tokens.filter((token, index) => {
    const response = responses[index];
    return (
      response &&
      !response.success &&
      response.error &&
      INVALID_TOKEN_CODES.has(response.error.code)
    );
  });

  await Promise.all(
    invalid.map((token) => db.doc(`users/${uid}/devices/${token}`).delete()),
  );
  return invalid;
}

module.exports = {
  INVALID_TOKEN_CODES,
  fetchTokens,
  pruneInvalidTokens,
  toDate,
};

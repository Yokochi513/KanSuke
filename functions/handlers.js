"use strict";

const {HttpsError} = require("firebase-functions/v2/identity");
const {evaluateSignup} = require("./allowlist");

/**
 * サインインメールを小文字・トリムして正規化する。
 * @param {?string} email
 * @return {string}
 */
function normalizeEmail(email) {
  return (email || "").trim().toLowerCase();
}

/**
 * `beforeUserCreated` の本体。allowlist を照合し、対象外は拒否、
 * 許可時は `users/{uid}` を allowlist 情報（name / color）から生成する。
 *
 * Firestore アクセスと serverTimestamp を引数で受け取り、テスト可能にする。
 *
 * @param {{data: {email?: string, uid?: string}}} event
 * @param {{doc: function(string): {get: function(): Promise<object>,
 *   set: function(object, object=): Promise<void>}}} db
 * @param {function(): *} serverTimestamp
 * @return {Promise<{allowed: boolean}>}
 */
async function handleBeforeCreate(event, db, serverTimestamp) {
  const email = normalizeEmail(event.data && event.data.email);
  const uid = event.data && event.data.uid;

  const snapshot = await db.doc(`allowlist/${email}`).get();
  const decision = evaluateSignup(
    email,
    snapshot.exists ? snapshot.data() : null,
  );

  if (!decision.allowed) {
    // allowlist 外はサインアップを拒否する（NFR-4 / 基本設計 §2.1）。
    throw new HttpsError("permission-denied", "利用権限がありません");
  }

  const now = serverTimestamp();
  await db.doc(`users/${uid}`).set(
    {
      name: decision.user.name,
      email: decision.user.email,
      color: decision.user.color,
      createdAt: now,
      updatedAt: now,
    },
    {merge: true},
  );

  return decision;
}

module.exports = {handleBeforeCreate, normalizeEmail};

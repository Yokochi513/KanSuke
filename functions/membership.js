"use strict";

// カレンダーのメンバー管理（FR-8 / Issue #89）。
//
// `memberIds` / `ownerId` は Security Rules でクライアントからの書き換えを
// 禁止しているため、メンバーの削除・退出・オーナー移譲はここを唯一の経路とする。
// 権限モデル:
// - メンバーの削除・カレンダー名の変更・オーナー移譲: オーナーのみ
// - 退出: メンバー本人（オーナーは移譲するまで退出できない）
//
// Firestore アクセスと serverTimestamp を引数で受け取り、単体テスト可能にする。

const {HttpsError} = require("firebase-functions/v2/https");

/**
 * `ownerId` を解決する（Issue #89）。バックフィル
 * （scripts/backfill-calendar-owner-id.js）完了までの後方互換として、
 * 欠損時は作成者をオーナーとみなす（`firestore.rules` の `calendarOwnerId` と対応）。
 *
 * @param {object} calendar `calendars/{id}` のデータ。
 * @return {string} オーナーの uid。
 */
function ownerIdOf(calendar) {
  return calendar.ownerId || calendar.creatorId;
}

/**
 * 呼び出し元の uid を検証する。
 *
 * @param {?string} uid 認証済みの uid。
 * @return {string}
 */
function requireUid(uid) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "サインインが必要です。");
  }
  return uid;
}

/**
 * Callable の引数が非空文字列であることを検証する。
 *
 * @param {*} value 検証する値。
 * @param {string} name 引数名（エラーメッセージ用）。
 * @return {string}
 */
function requireString(value, name) {
  if (typeof value !== "string" || value === "") {
    throw new HttpsError("invalid-argument", `${name} を指定してください。`);
  }
  return value;
}

/**
 * トランザクション内でカレンダーを読み、存在を検証する。
 *
 * @param {object} transaction Firestore のトランザクション。
 * @param {object} ref `calendars/{id}` の DocumentReference。
 * @return {Promise<object>} カレンダーのデータ。
 */
async function readCalendar(transaction, ref) {
  const snapshot = await transaction.get(ref);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "カレンダーが見つかりません。");
  }
  return snapshot.data();
}

/**
 * メンバーを削除する（オーナーのみ）。
 *
 * オーナー自身は指定できない（先にオーナーを移譲すること）。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, calendarId: *, targetUid: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function removeMember(db, request, serverTimestamp) {
  const uid = requireUid(request.uid);
  const calendarId = requireString(request.calendarId, "calendarId");
  const targetUid = requireString(request.targetUid, "targetUid");

  const ref = db.doc(`calendars/${calendarId}`);
  await db.runTransaction(async (transaction) => {
    const calendar = await readCalendar(transaction, ref);
    if (ownerIdOf(calendar) !== uid) {
      throw new HttpsError(
        "permission-denied",
        "メンバーを削除できるのはオーナーだけです。",
      );
    }
    if (targetUid === uid) {
      throw new HttpsError(
        "failed-precondition",
        "オーナー自身は削除できません。先にオーナーを移譲してください。",
      );
    }
    const memberIds = calendar.memberIds || [];
    if (!memberIds.includes(targetUid)) {
      throw new HttpsError(
        "failed-precondition",
        "指定されたメンバーはこのカレンダーに参加していません。",
      );
    }
    transaction.update(ref, {
      memberIds: memberIds.filter((id) => id !== targetUid),
      updatedAt: serverTimestamp(),
    });
  });
}

/**
 * カレンダーから退出する（メンバー本人）。
 *
 * オーナーは移譲するまで退出できない。カレンダーの削除機能が無いため、
 * 最後の1人の退出も当面できない（残ったカレンダーが誰からも見えなくなるため）。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, calendarId: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function leaveCalendar(db, request, serverTimestamp) {
  const uid = requireUid(request.uid);
  const calendarId = requireString(request.calendarId, "calendarId");

  const ref = db.doc(`calendars/${calendarId}`);
  await db.runTransaction(async (transaction) => {
    const calendar = await readCalendar(transaction, ref);
    const memberIds = calendar.memberIds || [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        "permission-denied",
        "このカレンダーに参加していません。",
      );
    }
    if (memberIds.length === 1) {
      throw new HttpsError(
        "failed-precondition",
        "最後の1人は退出できません。",
      );
    }
    if (ownerIdOf(calendar) === uid) {
      throw new HttpsError(
        "failed-precondition",
        "オーナーは退出できません。先に他のメンバーへオーナーを移譲してください。",
      );
    }
    transaction.update(ref, {
      memberIds: memberIds.filter((id) => id !== uid),
      updatedAt: serverTimestamp(),
    });
  });
}

/**
 * オーナーを他のメンバーへ移譲する（オーナーのみ）。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, calendarId: *, targetUid: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function transferOwnership(db, request, serverTimestamp) {
  const uid = requireUid(request.uid);
  const calendarId = requireString(request.calendarId, "calendarId");
  const targetUid = requireString(request.targetUid, "targetUid");

  const ref = db.doc(`calendars/${calendarId}`);
  await db.runTransaction(async (transaction) => {
    const calendar = await readCalendar(transaction, ref);
    if (ownerIdOf(calendar) !== uid) {
      throw new HttpsError(
        "permission-denied",
        "オーナーを移譲できるのはオーナーだけです。",
      );
    }
    const memberIds = calendar.memberIds || [];
    if (!memberIds.includes(targetUid)) {
      throw new HttpsError(
        "failed-precondition",
        "移譲先はこのカレンダーのメンバーである必要があります。",
      );
    }
    transaction.update(ref, {
      ownerId: targetUid,
      updatedAt: serverTimestamp(),
    });
  });
}

module.exports = {
  leaveCalendar,
  ownerIdOf,
  removeMember,
  transferOwnership,
};

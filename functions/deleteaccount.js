"use strict";

// アカウント削除（アプリ内からの退会導線、Issue #102）。
//
// Firebase Authentication のユーザー削除・他人のカレンダーの更新・本人以外が
// 混ざるコレクションの整理は Security Rules だけでは行えないため、退会処理は
// この Callable（Admin SDK）に一本化する。クライアントから直接 Auth の
// `delete()` は呼ばない。
//
// 削除対象データの扱い（基本設計 §2.4 / Issue #102 の決定事項）:
// - 本人だけが参加するカレンダー: 本体・配下の予定（`events`）・その予定の
//   `reminders`・カレンダーに紐づく `invites` ごと削除する。
// - 他メンバーがいる共有カレンダー: `memberIds` から本人を除外（＝退出）。予定は
//   残す（他メンバーの表示を壊さないため）。本人がオーナーなら、本人以外の先頭
//   メンバーへオーナーを自動移譲してから退出する（オーナー不在を作らない）。
// - 本人が発行した招待（`invites.invitedBy == uid`）: すべて削除する。
// - 本人が設定した `reminders`（`reminders.ownerId == uid`、個人・共有問わず）:
//   すべて削除する。`reminders` に `calendarId` は無いため、退会者に紐づく
//   リマインドは発行者（`ownerId`）で引いて消すのが確実で、これで個人カレンダーの
//   予定分（設定者は本人のみ）と、共有予定に本人が付けた分の両方が片付く。
// - `users/{uid}/devices/*` → `users/{uid}` → Auth ユーザーの順で削除する。
//
// Auth ユーザーの削除は**最後**に行い、途中で失敗しても再実行で続きから片付く
// （冪等）ようにする。各ステップは現在の状態を都度クエリするため、既に消えた
// ものは空振りし、二重実行でも壊れない。
//
// Firestore / Admin Auth / serverTimestamp を引数で受け取り、単体テスト可能にする。

const {HttpsError} = require("firebase-functions/v2/https");

/** 1 バッチで扱う書き込み件数の上限（Firestore の上限 500 に余裕を持たせる）。 */
const BATCH_LIMIT = 400;

/**
 * 呼び出し元の uid を検証する。他人の uid を `data` で渡されても、削除対象は
 * 常にこの認証済み uid に固定する（本人以外は削除できない）。
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
 * `ownerId` を解決する（`membership.js` と同じ後方互換規則、Issue #89）。
 * 欠損時は作成者をオーナーとみなす。
 *
 * @param {object} calendar `calendars/{id}` のデータ。
 * @return {string} オーナーの uid。
 */
function ownerIdOf(calendar) {
  return calendar.ownerId || calendar.creatorId;
}

/**
 * DocumentReference の配列をバッチ分割して削除する。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {object[]} refs 削除する DocumentReference。
 * @return {Promise<void>}
 */
async function deleteRefs(db, refs) {
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + BATCH_LIMIT)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

/**
 * クエリ（またはコレクション）に一致する全ドキュメントを削除する。
 *
 * @param {object} query `get()` を持つ Query / CollectionReference。
 * @param {object} db Firestore（Admin SDK）。
 * @return {Promise<number>} 削除した件数。
 */
async function deleteQuery(query, db) {
  const snapshot = await query.get();
  await deleteRefs(db, snapshot.docs.map((doc) => doc.ref));
  return snapshot.docs.length;
}

/**
 * 本人だけが参加するカレンダーを、配下の予定・招待ごと削除する。
 *
 * `reminders` はカレンダー横断でまとめて消す（`deleteAccount` の後段）ため、
 * ここでは扱わない。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {object} calendarRef 削除するカレンダーの DocumentReference。
 * @return {Promise<void>}
 */
async function deleteSoloCalendar(db, calendarRef) {
  await deleteQuery(
    db.collection("events").where("calendarId", "==", calendarRef.id),
    db,
  );
  await deleteQuery(
    db.collection("invites").where("calendarId", "==", calendarRef.id),
    db,
  );
  await calendarRef.delete();
}

/**
 * 共有カレンダーから本人を退出させる。本人がオーナーなら、本人以外の先頭
 * メンバーへオーナーを移譲してから退出する（オーナー不在を作らない）。
 *
 * @param {object} calendarRef 対象カレンダーの DocumentReference。
 * @param {object} calendar カレンダーのデータ。
 * @param {string} uid 退会する本人。
 * @param {string[]} others 本人以外のメンバー（1 人以上）。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function leaveSharedCalendar(
  calendarRef,
  calendar,
  uid,
  others,
  serverTimestamp,
) {
  const patch = {memberIds: others, updatedAt: serverTimestamp()};
  if (ownerIdOf(calendar) === uid) {
    // 決定的な移譲先: 本人以外の先頭メンバー（Issue #102 の決定事項）。
    patch.ownerId = others[0];
  }
  await calendarRef.update(patch);
}

/**
 * アカウントを削除する（本人のみ、Issue #102）。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {{deleteUser: function(string): Promise<void>}} auth Admin Auth。
 * @param {{uid: ?string}} request 呼び出し元。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function deleteAccount(db, auth, request, serverTimestamp) {
  const uid = requireUid(request.uid);

  // 1. 本人が参加する全カレンダーを、単独／共有で振り分けて処理する。
  const calendars = await db
    .collection("calendars")
    .where("memberIds", "array-contains", uid)
    .get();
  for (const doc of calendars.docs) {
    const calendar = doc.data();
    const others = (calendar.memberIds || []).filter((id) => id !== uid);
    if (others.length === 0) {
      await deleteSoloCalendar(db, doc.ref);
    } else {
      await leaveSharedCalendar(
        doc.ref,
        calendar,
        uid,
        others,
        serverTimestamp,
      );
    }
  }

  // 2. 本人が発行した招待（どのカレンダー宛でも）を削除する。
  await deleteQuery(
    db.collection("invites").where("invitedBy", "==", uid),
    db,
  );

  // 3. 本人が設定したリマインドを削除する（個人・共有問わず）。
  await deleteQuery(
    db.collection("reminders").where("ownerId", "==", uid),
    db,
  );

  // 4. デバイストークン → ユーザードキュメントの順に削除する。
  await deleteQuery(db.collection(`users/${uid}/devices`), db);
  const userRef = db.doc(`users/${uid}`);
  const userSnapshot = await userRef.get();
  if (userSnapshot.exists) {
    await userRef.delete();
  }

  // 5. 最後に Auth ユーザーを削除する。既に消えていれば成功扱い（冪等）。
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (!error || error.code !== "auth/user-not-found") {
      throw error;
    }
  }
}

module.exports = {
  deleteAccount,
  ownerIdOf,
};

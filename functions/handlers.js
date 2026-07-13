"use strict";

const {buildInitialProfile, personalCalendarName} = require("./signup");

/**
 * `beforeUserCreated` の本体（基本設計 §2.1）。
 *
 * サインアップを拒否せず、新規アカウントの初期データを作る:
 * - `users/{uid}`: ID プロバイダの表示名・メールと、初期の識別色（FR-2）。
 * - `calendars/{uuid}`: 本人だけが参加する個人カレンダー（FR-8）。
 *   ドキュメント ID は UUID（アプリのカレンダー作成と同じ規約）。
 *   本人が作成者かつオーナー（`ownerId`、Issue #89）になる。
 *
 * アカウント作成時にしか発火しないため、ここで作った個人カレンダーが
 * 各ユーザーの最初の表示対象になる。
 *
 * Firestore アクセス・serverTimestamp・UUID 生成を引数で受け取り、テスト可能にする。
 *
 * @param {{data: {email?: string, uid?: string, displayName?: string}}} event
 * @param {{doc: function(string): {set: function(object, object=): Promise<void>}}} db
 * @param {function(): *} serverTimestamp
 * @param {function(): string} newId
 * @return {Promise<{uid: string, calendarId: string,
 *   profile: {name: string, email: string, color: string}}>}
 */
async function handleBeforeCreate(event, db, serverTimestamp, newId) {
  const data = (event && event.data) || {};
  const uid = data.uid;
  const profile = buildInitialProfile({
    uid,
    email: data.email,
    displayName: data.displayName,
  });
  const now = serverTimestamp();

  await db.doc(`users/${uid}`).set(
    {...profile, createdAt: now, updatedAt: now},
    {merge: true},
  );

  const calendarId = newId();
  await db.doc(`calendars/${calendarId}`).set({
    name: personalCalendarName(profile.name),
    memberIds: [uid],
    creatorId: uid,
    ownerId: uid,
    createdAt: now,
    updatedAt: now,
  });

  return {uid, calendarId, profile};
}

module.exports = {handleBeforeCreate};

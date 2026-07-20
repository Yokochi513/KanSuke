"use strict";

// 予定の追加・変更・削除の共有通知（Issue #77、要件定義 FR-6 / FR-8）。
//
// 家族の誰かが予定を作成/更新/削除したとき、同じカレンダーの参加者のうち
// **操作者本人を除くメンバー**の全デバイスへ FCM 通知する。FR-5 のリマインド
// （開始前のお知らせ、Issue #14 / reminders.js）とは別物で、こちらは「変更の
// お知らせ」。
//
// トークン取得・無効トークン削除・時刻正規化は fcm.js を再利用する（Issue #14 と
// 共通化）。Firestore / FCM / 現在時刻を引数で受け取り、単体テスト可能にする。

const {fetchTokens, pruneInvalidTokens, toDate} = require("./fcm");

/**
 * 同一予定への連続編集で通知が過剰にならないよう、「変更」通知を抑制する窓（ミリ秒）。
 *
 * リーディングエッジのスロットル: 直近の送信からこの時間内の「変更」通知は送らない
 * （送信時刻を更新しないので、窓を超えれば次の変更で再び届く）。作成・削除は
 * 重要度が高く回数も少ないため抑制しない。
 */
const UPDATE_THROTTLE_MS = 5 * 60 * 1000;

/** 通知の抑制状態（直近の送信時刻）を持つコレクション。 */
const STATE_COLLECTION = "eventNotifications";

/** 操作者名を解決できないときのフォールバック表示。 */
const UNKNOWN_ACTOR_NAME = "メンバー";

const WEEKDAYS_JA = ["日", "月", "火", "水", "木", "金", "土"];

/**
 * 予定の変更を作成/更新/削除に分類する。
 *
 * - 物理削除（`after` が無い）は定期パージやアカウント削除の後始末であり、
 *   利用者の操作ではないため通知しない（削除はソフト削除で表現される）。
 * - 「更新」は共有される項目（タイトル・日時・種別・参加者など）が実際に
 *   変わったときだけ対象にする。`reminderOffsets` は各自の個人設定、
 *   `updatedAt` / `updatedBy` は監査用のため、それだけの変更では通知しない。
 *
 * @param {?object} before 変更前のデータ（作成時は null）。
 * @param {?object} after 変更後のデータ（物理削除時は null）。
 * @return {?{action: string, event: object, operatorId: ?string}}
 *   通知対象なら分類結果、対象外なら null。
 */
function classifyChange(before, after) {
  if (!after) return null;

  const wasActive = Boolean(before) && before.deleted !== true;
  const isActive = after.deleted !== true;

  let action = null;
  if (!wasActive && isActive) {
    action = "created";
  } else if (wasActive && !isActive) {
    action = "deleted";
  } else if (wasActive && isActive && hasMeaningfulChange(before, after)) {
    action = "updated";
  }
  if (!action) return null;

  return {action, event: after, operatorId: after.updatedBy || null};
}

/**
 * 共有される項目に変化があるかを判定する（「更新」通知の要否）。
 *
 * 個人設定（`reminderOffsets`）や監査項目（`updatedAt` / `updatedBy`）だけの
 * 変更は「変化なし」とみなし、無用な通知を避ける。
 *
 * @param {object} before 変更前のデータ。
 * @param {object} after 変更後のデータ。
 * @return {boolean} 共有項目が変わっていれば true。
 */
function hasMeaningfulChange(before, after) {
  const timeChanged = (a, b) => {
    const da = toDate(a);
    const db = toDate(b);
    if (!da || !db) return da !== db;
    return da.getTime() !== db.getTime();
  };

  if (before.title !== after.title) return true;
  if (timeChanged(before.startAt, after.startAt)) return true;
  if (timeChanged(before.endAt, after.endAt)) return true;
  if (Boolean(before.allDay) !== Boolean(after.allDay)) return true;
  if ((before.type || null) !== (after.type || null)) return true;
  if ((before.memo || "") !== (after.memo || "")) return true;
  if ((before.calendarId || null) !== (after.calendarId || null)) return true;
  if (!arraysEqualAsSet(before.participantIds, after.participantIds)) {
    return true;
  }
  if ((before.recurrenceFrequency || null) !== (after.recurrenceFrequency ||
    null)) {
    return true;
  }
  if ((before.recurrenceCount || null) !== (after.recurrenceCount || null)) {
    return true;
  }
  return false;
}

/**
 * 参加者 ID の集合が同じかを順不同で比較する。
 *
 * @param {*} a 変更前の participantIds。
 * @param {*} b 変更後の participantIds。
 * @return {boolean} 集合として一致すれば true。
 */
function arraysEqualAsSet(a, b) {
  const setA = new Set(Array.isArray(a) ? a : []);
  const setB = new Set(Array.isArray(b) ? b : []);
  if (setA.size !== setB.size) return false;
  for (const value of setA) {
    if (!setB.has(value)) return false;
  }
  return true;
}

/**
 * 予定の日付（と開始時刻）を日本語・日本時間（JST）で表す。
 *
 * 実行リージョンは asia-northeast1、家庭内運用も日本時間のため JST で表示する。
 * 終日予定は時刻を出さない。
 *
 * @param {*} startAt 予定の開始時刻。
 * @param {boolean} allDay 終日予定か。
 * @return {string} 例 "7月14日(火) 21:00" / 終日 "7月14日(火)"。
 */
function formatEventDate(startAt, allDay) {
  const date = toDate(startAt);
  if (!date) return "";

  // JST（UTC+9）に変換し、UTC の各要素として読む（環境の TZ に依存させない）。
  const jst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  const month = jst.getUTCMonth() + 1;
  const day = jst.getUTCDate();
  const weekday = WEEKDAYS_JA[jst.getUTCDay()];
  const dateStr = `${month}月${day}日(${weekday})`;
  if (allDay) return dateStr;

  const hh = String(jst.getUTCHours()).padStart(2, "0");
  const mm = String(jst.getUTCMinutes()).padStart(2, "0");
  return `${dateStr} ${hh}:${mm}`;
}

/**
 * 通知のタイトル・本文を組み立てる。
 *
 * 操作者・予定タイトル・日付・操作種別を含める（Issue #77 の受け入れ条件）。
 *
 * @param {string} action "created" / "updated" / "deleted"。
 * @param {object} event 予定データ。
 * @param {string} operatorName 操作者の表示名。
 * @return {{title: string, body: string}} FCM の notification。
 */
function buildMessage(action, event, operatorName) {
  const verb = {
    created: "追加",
    updated: "変更",
    deleted: "削除",
  }[action];
  const eventTitle = event.title || "予定";
  const dateStr = formatEventDate(event.startAt, event.allDay === true);

  return {
    title: `${operatorName}さんが予定を${verb}しました`,
    body: dateStr ? `${eventTitle}（${dateStr}）` : eventTitle,
  };
}

/**
 * カレンダー参加者のうち操作者を除いた配信先を求める。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {string} calendarId 予定のカレンダー。
 * @param {?string} operatorId 操作者の uid。
 * @return {Promise<string[]>} 配信先ユーザーの uid。
 */
async function resolveRecipients(db, calendarId, operatorId) {
  if (!calendarId) return [];
  const snapshot = await db.doc(`calendars/${calendarId}`).get();
  if (!snapshot.exists) return [];
  const memberIds = snapshot.data().memberIds || [];
  return memberIds.filter((uid) => uid && uid !== operatorId);
}

/**
 * 操作者の表示名を解決する（`users/{uid}.name`）。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {?string} operatorId 操作者の uid。
 * @return {Promise<string>} 表示名（解決不能ならフォールバック）。
 */
async function resolveOperatorName(db, operatorId) {
  if (!operatorId) return UNKNOWN_ACTOR_NAME;
  const snapshot = await db.doc(`users/${operatorId}`).get();
  const name = snapshot.exists && snapshot.data().name;
  return typeof name === "string" && name !== "" ? name : UNKNOWN_ACTOR_NAME;
}

/**
 * 「変更」通知をスロットルすべきかを判定する（過剰通知の抑制、Issue #77）。
 *
 * 直近の送信から `UPDATE_THROTTLE_MS` 以内の「更新」は抑制する。作成・削除は
 * 抑制しない。
 *
 * @param {string} action 操作種別。
 * @param {?Date} lastNotifiedAt 直近の送信時刻。
 * @param {Date} now 現在時刻。
 * @return {boolean} 抑制するなら true。
 */
function shouldThrottle(action, lastNotifiedAt, now) {
  if (action !== "updated" || !lastNotifiedAt) return false;
  return now.getTime() - lastNotifiedAt.getTime() < UPDATE_THROTTLE_MS;
}

/**
 * 配信先の全デバイスへ通知を送り、無効トークンを削除する。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {object} messaging FCM。
 * @param {string[]} recipients 配信先ユーザーの uid。
 * @param {{notification: object, data: object}} payload FCM ペイロード。
 * @return {Promise<{sent: number, prunedTokens: number}>} 送信結果。
 */
async function sendToRecipients(db, messaging, recipients, payload) {
  let sent = 0;
  let prunedTokens = 0;

  for (const uid of recipients) {
    const tokens = await fetchTokens(db, uid);
    if (tokens.length === 0) continue;

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: payload.notification,
      data: payload.data,
    });

    sent += response.successCount || 0;
    const pruned = await pruneInvalidTokens(
      db,
      uid,
      tokens,
      response.responses || [],
    );
    prunedTokens += pruned.length;
  }

  return {sent, prunedTokens};
}

/**
 * 予定変更の共有通知を送る（`onEventWrite` の通知担当、Issue #77）。
 *
 * 作成/更新/削除を分類し、同カレンダー参加者（操作者除く）の全デバイスへ FCM 通知
 * する。過剰通知を防ぐため「更新」は直近送信から一定時間はスロットルする。無効
 * トークンは削除する。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {{sendEachForMulticast: function(object): Promise<object>}} messaging FCM。
 * @param {{eventId: string, before: ?object, after: ?object}} change onWrite の変更。
 * @param {{now: function(): Date}} deps 現在時刻。
 * @return {Promise<{action: ?string, notified: number, recipients: number,
 *   prunedTokens: number, throttled: boolean}>} 処理結果。
 */
async function notifyEventChange(db, messaging, change, deps) {
  const skip = (action = null, throttled = false) => ({
    action,
    notified: 0,
    recipients: 0,
    prunedTokens: 0,
    throttled,
  });

  const classified = classifyChange(change.before, change.after);
  if (!classified) return skip();

  const {action, event, operatorId} = classified;
  const recipients = await resolveRecipients(db, event.calendarId, operatorId);
  if (recipients.length === 0) return skip(action);

  const now = deps.now();
  const stateRef = db.doc(`${STATE_COLLECTION}/${change.eventId}`);
  const stateSnapshot = await stateRef.get();
  const lastNotifiedAt = stateSnapshot.exists ?
    toDate(stateSnapshot.data().lastNotifiedAt) :
    null;

  if (shouldThrottle(action, lastNotifiedAt, now)) {
    return skip(action, true);
  }

  const operatorName = await resolveOperatorName(db, operatorId);
  const payload = {
    notification: buildMessage(action, event, operatorName),
    // クライアントがリマインド通知（`{eventId}`）と区別し、該当カレンダー/予定へ
    // 遷移できるようにする。
    data: {
      type: "eventChange",
      action,
      eventId: change.eventId,
      calendarId: event.calendarId || "",
    },
  };

  const {sent, prunedTokens} = await sendToRecipients(
    db,
    messaging,
    recipients,
    payload,
  );

  await stateRef.set({lastNotifiedAt: now, lastAction: action});

  return {
    action,
    notified: sent,
    recipients: recipients.length,
    prunedTokens,
    throttled: false,
  };
}

module.exports = {
  buildMessage,
  classifyChange,
  formatEventDate,
  hasMeaningfulChange,
  notifyEventChange,
  shouldThrottle,
};

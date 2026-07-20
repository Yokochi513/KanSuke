"use strict";

// リマインド通知（FR-5 / 基本設計 §5.1、Issue #14）。
//
// 2 つの Function の本体:
// - `syncEventReminders`: `events/{id}` の onWrite で、その予定の `reminders` を
//   旧分破棄 → 再生成する（`triggerAt = startAt - offset分`）。
// - `sendDueReminders`: 毎分のスケジュールで `triggerAt <= now && sent == false`
//   を抽出し、配信先の全デバイスへ FCM 送信して `sent = true` にする。
//
// リマインドは**各自が自分の分だけ設定する**（基本設計 §3.2）。
// `events.reminderOffsets` は `{uid: [分, ...]}` の map で、reminder は
// 「設定した本人（map のキー）」にだけ届く（`reminders.ownerId` = そのキー）。
// 旧形式（予定で共有する `number[]`）のドキュメントは無視する（移行せず破棄）。
// 「希望者への配信」（購読モデル）は将来拡張のためスコープ外。
//
// Firestore / FCM / 現在時刻 / UUID 生成を引数で受け取り、単体テスト可能にする。
//
// トークン取得・無効トークン削除・時刻正規化は予定変更通知（Issue #77）と共通の
// ため fcm.js に切り出して再利用する。

const {fetchTokens, pruneInvalidTokens, toDate} = require("./fcm");

/** 1 回の実行で送信する reminders の上限（毎分実行のため十分な数）。 */
const DUE_BATCH_LIMIT = 200;

/**
 * `reminderOffsets`（開始 n 分前）を正規化する。
 *
 * 0 以上の整数だけを残し、重複を除いて昇順にする。
 *
 * @param {*} offsets 予定の `reminderOffsets`。
 * @return {number[]} 正規化した offset（分）。
 */
function normalizeOffsets(offsets) {
  if (!Array.isArray(offsets)) return [];
  const valid = offsets.filter(
    (offset) => Number.isInteger(offset) && offset >= 0,
  );
  return [...new Set(valid)].sort((a, b) => a - b);
}

/**
 * `reminderOffsets`（`{uid: [分, ...]}`）を「uid → 正規化した offset」に整える。
 *
 * 旧形式（`number[]`）や不正な値は無視する（移行せず破棄、Issue #14）。
 * 空配列の uid は落とし、uid の昇順で返す（比較を安定させるため）。
 *
 * @param {*} reminderOffsets 予定の `reminderOffsets`。
 * @return {[string, number[]][]} uid と offset（分）の組。
 */
function offsetsByOwner(reminderOffsets) {
  if (
    !reminderOffsets ||
    typeof reminderOffsets !== "object" ||
    Array.isArray(reminderOffsets)
  ) {
    return [];
  }

  return Object.keys(reminderOffsets)
    .sort()
    .map((uid) => [uid, normalizeOffsets(reminderOffsets[uid])])
    .filter(([, offsets]) => offsets.length > 0);
}

/**
 * 予定から `reminders` のドキュメントを組み立てる（基本設計 §3.2 / §5.1）。
 *
 * 配信先は「offset を設定した本人」。削除済み・開始時刻なし・設定なしの予定は 0 件。
 * 配信時刻が既に過ぎている分は作らない（作ると `sendDueReminders` が直後に
 * 「過ぎた予定」の通知を送ってしまうため。例: 開始 10 分前に「60 分前」を
 * 指定して作成した予定）。
 *
 * @param {string} eventId 元 Event の ID。
 * @param {?object} event `events/{id}` のデータ（削除済みなら `deleted: true`）。
 * @param {{now: function(): Date, newId: function(): string}} deps 現在時刻と ID 生成。
 * @return {{id: string, data: {eventId: string, ownerId: string,
 *   triggerAt: Date, sent: boolean}}[]} 生成する reminders。
 */
function buildReminders(eventId, event, deps) {
  if (!event || event.deleted === true) return [];

  const startAt = toDate(event.startAt);
  if (!startAt) return [];

  const now = deps.now();
  const reminders = [];

  for (const [ownerId, offsets] of offsetsByOwner(event.reminderOffsets)) {
    for (const offset of offsets) {
      const triggerAt = new Date(startAt.getTime() - offset * 60 * 1000);
      if (triggerAt.getTime() <= now.getTime()) continue;
      reminders.push({
        id: deps.newId(),
        data: {eventId, ownerId, triggerAt, sent: false},
      });
    }
  }
  return reminders;
}

/**
 * reminders の再生成が必要な変更かを判定する。
 *
 * タイトルやメモだけの更新で再生成すると、送信済み（`sent: true`）の reminder が
 * 未送信として作り直され、多重送信になる。`startAt` / `reminderOffsets` /
 * `deleted` が変わった時だけ再生成する（基本設計 §5.1）。
 *
 * @param {?object} before 変更前のデータ（作成時は null）。
 * @param {?object} after 変更後のデータ（削除時は null）。
 * @return {boolean} 再生成が必要なら true。
 */
function needsRebuild(before, after) {
  if (!before || !after) return true;

  const startChanged = (() => {
    const a = toDate(before.startAt);
    const b = toDate(after.startAt);
    if (!a || !b) return a !== b;
    return a.getTime() !== b.getTime();
  })();

  const sameOffsets =
    JSON.stringify(offsetsByOwner(before.reminderOffsets)) ===
    JSON.stringify(offsetsByOwner(after.reminderOffsets));

  return (
    startChanged || before.deleted !== after.deleted || !sameOffsets
  );
}

/**
 * 予定の reminders を再生成する（`onEventWrite` の本体、基本設計 §5.1）。
 *
 * 旧分をすべて削除してから作り直す。予定が削除（ソフト削除・物理削除）された
 * 場合は削除だけを行う。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {{eventId: string, before: ?object, after: ?object}} change onWrite の変更。
 * @param {{now: function(): Date, newId: function(): string}} deps 現在時刻と ID 生成。
 * @return {Promise<{deleted: number, created: number}>} 削除・生成した件数。
 */
async function syncEventReminders(db, change, deps) {
  if (!needsRebuild(change.before, change.after)) {
    return {deleted: 0, created: 0};
  }

  const existing = await db
    .collection("reminders")
    .where("eventId", "==", change.eventId)
    .get();

  const batch = db.batch();
  for (const doc of existing.docs) {
    batch.delete(doc.ref);
  }

  const reminders = buildReminders(change.eventId, change.after, deps);
  for (const reminder of reminders) {
    batch.set(db.doc(`reminders/${reminder.id}`), reminder.data);
  }
  await batch.commit();

  return {deleted: existing.docs.length, created: reminders.length};
}

/**
 * 配信時刻が到来した未送信の reminders を取得する。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {Date} now 現在時刻。
 * @return {Promise<object[]>} reminders の DocumentSnapshot。
 */
async function fetchDueReminders(db, now) {
  const snapshot = await db
    .collection("reminders")
    .where("sent", "==", false)
    .where("triggerAt", "<=", now)
    .limit(DUE_BATCH_LIMIT)
    .get();
  return snapshot.docs;
}

/**
 * 通知本文の「あと n 分」表現。
 *
 * @param {number} minutes 開始までの分数（`startAt - triggerAt`）。
 * @return {string} 通知本文。
 */
function formatLeadTime(minutes) {
  if (minutes <= 0) return "まもなく開始します";
  if (minutes < 60) return `${minutes}分後に開始します`;
  if (minutes % 1440 === 0) return `${minutes / 1440}日後に開始します`;
  if (minutes % 60 === 0) return `${minutes / 60}時間後に開始します`;
  return `${minutes}分後に開始します`;
}

/**
 * 配信時刻が到来した reminders を送信する（`sendDueReminders` の本体、§5.1）。
 *
 * 多重送信防止のため、送信の可否によらず処理した reminder は `sent = true` に
 * する（トークン未登録・予定が消えた場合も同じ。時刻が変われば `onEventWrite`
 * が reminders を作り直すため再スケジュールされる）。
 *
 * @param {object} db Firestore（Admin SDK）。
 * @param {{sendEachForMulticast: function(object): Promise<object>}} messaging FCM。
 * @param {{now: function(): Date}} deps 現在時刻。
 * @return {Promise<{processed: number, sent: number, prunedTokens: number}>} 処理結果。
 */
async function sendDueReminders(db, messaging, deps) {
  const now = deps.now();
  const dueDocs = await fetchDueReminders(db, now);

  const events = new Map();
  const eventOf = async (eventId) => {
    if (!events.has(eventId)) {
      const snapshot = await db.doc(`events/${eventId}`).get();
      events.set(eventId, snapshot.exists ? snapshot.data() : null);
    }
    return events.get(eventId);
  };

  let sent = 0;
  let prunedTokens = 0;

  for (const doc of dueDocs) {
    const reminder = doc.data();
    const event = await eventOf(reminder.eventId);

    if (event && event.deleted !== true) {
      const tokens = await fetchTokens(db, reminder.ownerId);
      if (tokens.length > 0) {
        const startAt = toDate(event.startAt);
        const triggerAt = toDate(reminder.triggerAt);
        const minutes = startAt && triggerAt ?
          Math.round((startAt.getTime() - triggerAt.getTime()) / 60000) :
          0;

        const response = await messaging.sendEachForMulticast({
          tokens,
          notification: {
            title: event.title || "予定",
            body: formatLeadTime(minutes),
          },
          data: {eventId: reminder.eventId},
        });

        sent += response.successCount || 0;
        const pruned = await pruneInvalidTokens(
          db,
          reminder.ownerId,
          tokens,
          response.responses || [],
        );
        prunedTokens += pruned.length;
      }
    }

    await doc.ref.update({sent: true});
  }

  return {processed: dueDocs.length, sent, prunedTokens};
}

module.exports = {
  buildReminders,
  fetchDueReminders,
  formatLeadTime,
  needsRebuild,
  offsetsByOwner,
  sendDueReminders,
  syncEventReminders,
};

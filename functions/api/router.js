"use strict";

// 外部向け読み取り専用 REST API のルーティングとハンドラ（Issue #103）。
//
// **セキュリティ上の要**: この API は Admin SDK 経由で Firestore を読むため
// Security Rules を経由しない。したがって「呼び出し元 uid がカレンダーの
// `memberIds` に含まれること」を**必ずここで自前チェック**する（FR-8）。
// 漏れると全家庭のデータが露出する。カレンダー / 予定の取得は必ず
// `requireCalendarMembership()` を通すこと。
//
// Firestore アクセスを引数で受け取り、単体テスト可能にする。

const {ApiError, invalidArgument, notFound} = require("./errors");
const {
  parseIso,
  serializeCalendar,
  serializeEvent,
  serializeUser,
} = require("./serialize");

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;

/**
 * ページングカーソルを不透明な文字列にする。
 *
 * 中身は最後に返した予定の ID。利用者に構造を保証しないため base64url で包む。
 *
 * @param {string} eventId 予定 ID。
 * @return {string}
 */
function encodeCursor(eventId) {
  return Buffer.from(eventId, "utf8").toString("base64url");
}

/**
 * ページングカーソルを復号する。
 *
 * @param {string} cursor クエリで受け取った値。
 * @return {string} 予定 ID。
 */
function decodeCursor(cursor) {
  const decoded = Buffer.from(cursor, "base64url").toString("utf8");
  if (!decoded) throw invalidArgument("cursor が不正です。");
  return decoded;
}

/**
 * クエリから必須の文字列を取り出す。
 *
 * @param {object} query クエリパラメータ。
 * @param {string} name パラメータ名。
 * @return {string}
 */
function requireQuery(query, name) {
  const value = query[name];
  if (typeof value !== "string" || value === "") {
    throw invalidArgument(`${name} を指定してください。`);
  }
  return value;
}

/**
 * `limit` を検証する（既定 100・上限 500）。
 *
 * @param {*} value クエリの値。
 * @return {number}
 */
function parseLimit(value) {
  if (value === undefined || value === "") return DEFAULT_LIMIT;
  const limit = Number(value);
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
    throw invalidArgument(`limit は 1〜${MAX_LIMIT} の整数で指定してください。`);
  }
  return limit;
}

/**
 * カレンダーを読み、呼び出し元がメンバーであることを確認する。
 *
 * 「存在しない」と「メンバーでない」を区別せず 404 にして、存在の有無自体を
 * 漏らさない（Issue #103 の受け入れ条件）。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @param {string} calendarId カレンダー ID。
 * @return {Promise<object>} カレンダーのデータ。
 */
async function requireCalendarMembership(db, uid, calendarId) {
  const snapshot = await db.doc(`calendars/${calendarId}`).get();
  if (!snapshot.exists) throw notFound();
  const calendar = snapshot.data();
  const memberIds = calendar.memberIds || [];
  if (!memberIds.includes(uid)) throw notFound();
  return calendar;
}

/**
 * `GET /v1/me`。自分のプロフィール。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @return {Promise<object>}
 */
async function getMe(db, uid) {
  const snapshot = await db.doc(`users/${uid}`).get();
  if (!snapshot.exists) throw notFound();
  return serializeUser(uid, snapshot.data());
}

/**
 * `GET /v1/calendars`。自分が参加しているカレンダーだけを名前昇順で返す。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @return {Promise<object>}
 */
async function listCalendars(db, uid) {
  const result = await db
    .collection("calendars")
    .where("memberIds", "array-contains", uid)
    .orderBy("name")
    .get();
  return {
    calendars: result.docs.map((doc) => serializeCalendar(doc.id, doc.data())),
  };
}

/**
 * `GET /v1/calendars/{calendarId}`。メンバーでなければ 404。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @param {string} calendarId カレンダー ID。
 * @return {Promise<object>}
 */
async function getCalendar(db, uid, calendarId) {
  const calendar = await requireCalendarMembership(db, uid, calendarId);
  return serializeCalendar(calendarId, calendar);
}

/**
 * `GET /v1/events`。指定カレンダーの、期間内の予定を開始日時の昇順で返す。
 *
 * 期間は開始日時（`startAt`）が `from` 以上 `to` 未満のものを対象とする
 * （月表示のクエリと同じ絞り込み。複合インデックス
 * `(deleted, calendarId, startAt)` を使う）。`deleted == true` の予定は
 * トゥームストーンなので返さない。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @param {object} query クエリパラメータ。
 * @return {Promise<object>}
 */
async function listEvents(db, uid, query) {
  const calendarId = requireQuery(query, "calendarId");
  const from = parseIso(requireQuery(query, "from"));
  const to = parseIso(requireQuery(query, "to"));
  if (!from) throw invalidArgument("from は ISO 8601 で指定してください。");
  if (!to) throw invalidArgument("to は ISO 8601 で指定してください。");
  if (from.getTime() >= to.getTime()) {
    throw invalidArgument("from は to より前である必要があります。");
  }
  const limit = parseLimit(query.limit);

  await requireCalendarMembership(db, uid, calendarId);

  let firestoreQuery = db
    .collection("events")
    .where("deleted", "==", false)
    .where("calendarId", "==", calendarId)
    .where("startAt", ">=", from)
    .where("startAt", "<", to)
    .orderBy("startAt");

  if (typeof query.cursor === "string" && query.cursor !== "") {
    const cursorId = decodeCursor(query.cursor);
    const cursorDoc = await db.doc(`events/${cursorId}`).get();
    // 他カレンダーの ID をカーソルに詰めても、この検証で 400 になる
    // （カーソル経由で範囲外の予定を覗けないようにする）。
    if (!cursorDoc.exists || cursorDoc.data().calendarId !== calendarId) {
      throw invalidArgument("cursor が不正です。");
    }
    firestoreQuery = firestoreQuery.startAfter(cursorDoc);
  }

  // 次ページの有無を 1 件多く取って判定する（余分な 1 件は返さない）。
  const result = await firestoreQuery.limit(limit + 1).get();
  const docs = result.docs.slice(0, limit);
  const hasMore = result.docs.length > limit;

  return {
    events: docs.map((doc) => serializeEvent(doc.id, doc.data())),
    nextCursor: hasMore ? encodeCursor(docs[docs.length - 1].id) : null,
  };
}

/**
 * `GET /v1/events/{eventId}`。所属カレンダーのメンバーでなければ 404。
 *
 * @param {object} db Firestore。
 * @param {string} uid 呼び出し元。
 * @param {string} eventId 予定 ID。
 * @return {Promise<object>}
 */
async function getEvent(db, uid, eventId) {
  const snapshot = await db.doc(`events/${eventId}`).get();
  if (!snapshot.exists) throw notFound();
  const event = snapshot.data();
  if (event.deleted === true) throw notFound();
  if (!event.calendarId) throw notFound();
  await requireCalendarMembership(db, uid, event.calendarId);
  return serializeEvent(eventId, event);
}

/**
 * パスを正規化してセグメントに分ける。
 *
 * @param {string} path リクエストパス。
 * @return {string[]}
 */
function segmentsOf(path) {
  return String(path || "")
    .split("/")
    .filter((segment) => segment !== "");
}

/**
 * 認証済みリクエストを対応するハンドラへ振り分ける（読み取り専用・GET のみ）。
 *
 * @param {{db: object}} deps 依存。
 * @param {{method: string, path: string, query: object, uid: string}} request
 * @return {Promise<{status: number, body: object}>}
 */
async function handleApiRequest(deps, request) {
  const {db} = deps;
  const {uid} = request;
  const segments = segmentsOf(request.path);

  if (request.method !== "GET") {
    // v1 は読み取り専用。書き込み系は実装しない（Issue #103）。
    throw new ApiError("invalid_argument", "GET のみ対応しています。");
  }
  if (segments[0] !== "v1") throw notFound();

  const [, resource, id] = segments;
  if (segments.length === 2 && resource === "me") {
    return {status: 200, body: await getMe(db, uid)};
  }
  if (segments.length === 2 && resource === "calendars") {
    return {status: 200, body: await listCalendars(db, uid)};
  }
  if (segments.length === 3 && resource === "calendars") {
    return {status: 200, body: await getCalendar(db, uid, id)};
  }
  if (segments.length === 2 && resource === "events") {
    return {status: 200, body: await listEvents(db, uid, request.query || {})};
  }
  if (segments.length === 3 && resource === "events") {
    return {status: 200, body: await getEvent(db, uid, id)};
  }
  throw notFound();
}

module.exports = {
  DEFAULT_LIMIT,
  MAX_LIMIT,
  decodeCursor,
  encodeCursor,
  handleApiRequest,
};

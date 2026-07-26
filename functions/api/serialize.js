"use strict";

// Firestore ドキュメント → API レスポンス JSON への変換（Issue #103）。
//
// 時刻は API 境界で必ず ISO 8601（UTC, 例 `2026-07-14T09:00:00Z`）へ変換する。
// フィールドの読み取り規則（旧フィールド名へのフォールバック等）は
// `lib/models/event.dart` の `Event.fromMap` に一致させ、アプリが読める
// ドキュメントは API でも読めるようにする。

/**
 * Firestore の Timestamp / Date を ISO 8601（UTC）文字列にする。
 *
 * @param {*} value Timestamp・Date・null。
 * @return {?string} ISO 8601 文字列。変換できなければ null。
 */
function toIso(value) {
  if (value === null || value === undefined) return null;
  const date = typeof value.toDate === "function" ? value.toDate() : value;
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * ISO 8601 文字列を Date にする。
 *
 * @param {*} value クエリで受け取った文字列。
 * @return {?Date} 解釈できなければ null。
 */
function parseIso(value) {
  if (typeof value !== "string" || value === "") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * `users/{uid}` を `GET /v1/me` のレスポンスにする。
 *
 * @param {string} uid ユーザー ID。
 * @param {object} data ドキュメントのデータ。
 * @return {object}
 */
function serializeUser(uid, data) {
  return {
    uid,
    name: data.name || "",
    color: data.color || null,
  };
}

/**
 * `calendars/{id}` をレスポンスにする。
 *
 * `ownerId` 欠損時は `creatorId` をオーナーとみなす（membership.ownerIdOf と同じ
 * 後方互換、Issue #89）。
 *
 * @param {string} id カレンダー ID。
 * @param {object} data ドキュメントのデータ。
 * @return {object}
 */
function serializeCalendar(id, data) {
  return {
    id,
    name: data.name || "",
    ownerId: data.ownerId || data.creatorId || null,
    memberIds: data.memberIds || [],
  };
}

/**
 * `reminderOffsets` を `{uid: [分]}` として読む（Issue #14）。
 *
 * 旧形式（予定で共有する `number[]`）とキー欠落は「設定なし」として扱う
 * （`Event.fromMap` と同じ）。
 *
 * @param {*} value ドキュメントの値。
 * @return {object}
 */
function reminderOffsetsOf(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const offsetsByUid = {};
  for (const [uid, offsets] of Object.entries(value)) {
    if (!Array.isArray(offsets)) continue;
    offsetsByUid[uid] = offsets.filter((offset) => typeof offset === "number");
  }
  return offsetsByUid;
}

/**
 * `events/{id}` をレスポンスにする。
 *
 * `deleted` / `updatedBy` は内部管理用のため返さない（Issue #103）。繰り返し
 * 予定は v1 では展開せず、マスタのフィールドをそのまま返す。
 *
 * @param {string} id 予定 ID。
 * @param {object} data ドキュメントのデータ。
 * @return {object}
 */
function serializeEvent(id, data) {
  return {
    id,
    calendarId: data.calendarId,
    title: data.title || "",
    // 旧 `ownerId` 名のドキュメントへのフォールバック（Event.fromMap と同じ）。
    creatorId: data.creatorId || data.ownerId || null,
    participantIds: data.participantIds || [],
    startAt: toIso(data.startAt),
    endAt: toIso(data.endAt),
    allDay: data.allDay === true,
    type: data.type,
    memo: data.memo || "",
    reminderOffsets: reminderOffsetsOf(data.reminderOffsets),
    recurrenceFrequency: data.recurrenceFrequency || null,
    recurrenceCount:
      typeof data.recurrenceCount === "number" ? data.recurrenceCount : null,
    createdAt: toIso(data.createdAt),
    updatedAt: toIso(data.updatedAt),
  };
}

module.exports = {
  parseIso,
  serializeCalendar,
  serializeEvent,
  serializeUser,
  toIso,
};

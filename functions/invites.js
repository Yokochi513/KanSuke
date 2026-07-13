"use strict";

// 招待リンクによるカレンダー参加（FR-9 / Issue #90）。
//
// `memberIds` は Security Rules でクライアントからの書き換えを禁止しているため
// （Issue #89）、カレンダーに家族を追加する唯一の手段がこの招待リンクになる。
// `invites` コレクションもクライアントからは read/write 全面禁止で、発行・確認・
// 受諾・取り消し・一覧のすべてをこの Callable 経由（Admin SDK）で行う。
//
// 権限モデル:
// - 発行（createInvite）・一覧（listInvites）: そのカレンダーのメンバーなら誰でも
// - 取り消し（revokeInvite）: 発行者本人またはオーナー
// - 受諾（acceptInvite）: サインイン済みの誰でも（トークンの所持が資格）
//
// リンク漏洩のリスクは「有効期限・使用回数上限・取り消し」で緩和する。トークン
// 本体は Firestore に保存せず、SHA-256 ハッシュだけを保存する。
//
// Firestore アクセス・serverTimestamp・トークン生成・現在時刻を引数で受け取り、
// 単体テスト可能にする。

const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");

/** 招待リンクの既定の有効期限（24時間）。 */
const DEFAULT_EXPIRES_IN_MS = 24 * 60 * 60 * 1000;

/** 招待リンクの既定の使用回数上限（1回）。 */
const DEFAULT_MAX_USES = 1;

/**
 * 招待トークンを生成する（256bit、URL セーフ）。
 *
 * @return {string} トークン本体（保存せず、呼び出し元にだけ返す）。
 */
function generateToken() {
  return crypto.randomBytes(32).toString("base64url");
}

/**
 * トークンのハッシュ（SHA-256、hex）。Firestore にはこちらだけを保存する。
 *
 * @param {string} token トークン本体。
 * @return {string} ハッシュ。
 */
function hashToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

/**
 * `ownerId` を解決する（`membership.js` と同じ後方互換規則、Issue #89）。
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
 * Firestore の timestamp / Date / 数値をミリ秒に正規化する。
 *
 * @param {*} value 期限などの時刻。
 * @return {number} エポックミリ秒（解釈できない場合は 0）。
 */
function toMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return 0;
}

/**
 * 招待の有効性を検証する。無効な理由は `details.reason` で返し、UI が
 * 理由を出し分けられるようにする（受け入れ条件「理由が UI に表示される」）。
 *
 * @param {object} invite `invites/{id}` のデータ。
 * @param {number} nowMs 現在時刻（エポックミリ秒）。
 * @return {void}
 */
function assertUsable(invite, nowMs) {
  if (invite.revoked) {
    throw new HttpsError(
      "failed-precondition",
      "この招待リンクは取り消されています。",
      {reason: "revoked"},
    );
  }
  if (toMillis(invite.expiresAt) <= nowMs) {
    throw new HttpsError(
      "failed-precondition",
      "この招待リンクは有効期限が切れています。",
      {reason: "expired"},
    );
  }
  const maxUses = invite.maxUses || DEFAULT_MAX_USES;
  if ((invite.usedCount || 0) >= maxUses) {
    throw new HttpsError(
      "failed-precondition",
      "この招待リンクは使用済みです。",
      {reason: "used"},
    );
  }
}

/**
 * トークンから招待ドキュメントを引く（`tokenHash` の完全一致）。
 *
 * @param {object} db Firestore。
 * @param {string} token トークン本体。
 * @return {object} `invites` への Query。
 */
function inviteQuery(db, token) {
  return db
    .collection("invites")
    .where("tokenHash", "==", hashToken(token))
    .limit(1);
}

/**
 * 招待リンクを発行する（メンバーなら誰でも）。
 *
 * トークン本体は戻り値でだけ返し、Firestore にはハッシュだけを保存する。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, calendarId: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @param {{now?: function(): Date, token?: function(): string}} deps テスト用。
 * @return {Promise<{inviteId: string, token: string, expiresAt: string}>}
 */
async function createInvite(db, request, serverTimestamp, deps = {}) {
  const uid = requireUid(request.uid);
  const calendarId = requireString(request.calendarId, "calendarId");
  const now = (deps.now || (() => new Date()))();
  const token = (deps.token || generateToken)();

  const snapshot = await db.doc(`calendars/${calendarId}`).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "カレンダーが見つかりません。");
  }
  const memberIds = snapshot.data().memberIds || [];
  if (!memberIds.includes(uid)) {
    throw new HttpsError(
      "permission-denied",
      "招待リンクを発行できるのはカレンダーのメンバーだけです。",
    );
  }

  const expiresAt = new Date(now.getTime() + DEFAULT_EXPIRES_IN_MS);
  const ref = db.collection("invites").doc();
  await ref.set({
    calendarId,
    tokenHash: hashToken(token),
    invitedBy: uid,
    expiresAt,
    maxUses: DEFAULT_MAX_USES,
    usedCount: 0,
    revoked: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  return {inviteId: ref.id, token, expiresAt: expiresAt.toISOString()};
}

/**
 * 受諾前の確認（サインイン済みなら誰でも）。
 *
 * 未参加者は `calendars` / `users` を read できないため、参加前にカレンダー名と
 * 招待者名を知る経路はここだけになる。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, token: *}} request 呼び出し元と引数。
 * @param {{now?: function(): Date}} deps テスト用。
 * @return {Promise<{calendarId: string, calendarName: string,
 *   invitedByName: string, alreadyMember: boolean}>}
 */
async function previewInvite(db, request, deps = {}) {
  const uid = requireUid(request.uid);
  const token = requireString(request.token, "token");
  const nowMs = (deps.now || (() => new Date()))().getTime();

  const found = await inviteQuery(db, token).get();
  if (found.empty) {
    throw new HttpsError("not-found", "この招待リンクは無効です。", {
      reason: "not-found",
    });
  }
  const invite = found.docs[0].data();
  assertUsable(invite, nowMs);

  const calendarSnapshot = await db.doc(`calendars/${invite.calendarId}`).get();
  if (!calendarSnapshot.exists) {
    throw new HttpsError("not-found", "この招待リンクは無効です。", {
      reason: "not-found",
    });
  }
  const calendar = calendarSnapshot.data();
  const inviterSnapshot = await db.doc(`users/${invite.invitedBy}`).get();
  const inviter = inviterSnapshot.exists ? inviterSnapshot.data() : null;

  return {
    calendarId: invite.calendarId,
    calendarName: calendar.name || "",
    invitedByName: (inviter && inviter.name) || "",
    alreadyMember: (calendar.memberIds || []).includes(uid),
  };
}

/**
 * 招待を受諾してカレンダーに参加する。
 *
 * 既にメンバーの場合は成功扱い（冪等）で、使用回数も増やさない。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, token: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @param {{now?: function(): Date}} deps テスト用。
 * @return {Promise<{calendarId: string, alreadyMember: boolean}>}
 */
async function acceptInvite(db, request, serverTimestamp, deps = {}) {
  const uid = requireUid(request.uid);
  const token = requireString(request.token, "token");
  const nowMs = (deps.now || (() => new Date()))().getTime();

  const query = inviteQuery(db, token);
  return db.runTransaction(async (transaction) => {
    const found = await transaction.get(query);
    if (found.empty) {
      throw new HttpsError("not-found", "この招待リンクは無効です。", {
        reason: "not-found",
      });
    }
    const inviteDoc = found.docs[0];
    const invite = inviteDoc.data();
    assertUsable(invite, nowMs);

    const calendarRef = db.doc(`calendars/${invite.calendarId}`);
    const calendarSnapshot = await transaction.get(calendarRef);
    if (!calendarSnapshot.exists) {
      throw new HttpsError("not-found", "この招待リンクは無効です。", {
        reason: "not-found",
      });
    }
    const memberIds = calendarSnapshot.data().memberIds || [];
    if (memberIds.includes(uid)) {
      return {calendarId: invite.calendarId, alreadyMember: true};
    }

    transaction.update(calendarRef, {
      memberIds: [...memberIds, uid],
      updatedAt: serverTimestamp(),
    });
    transaction.update(inviteDoc.ref, {
      usedCount: (invite.usedCount || 0) + 1,
      updatedAt: serverTimestamp(),
    });
    return {calendarId: invite.calendarId, alreadyMember: false};
  });
}

/**
 * 招待リンクを取り消す（発行者本人またはカレンダーのオーナー）。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, inviteId: *}} request 呼び出し元と引数。
 * @param {function(): *} serverTimestamp
 * @return {Promise<void>}
 */
async function revokeInvite(db, request, serverTimestamp) {
  const uid = requireUid(request.uid);
  const inviteId = requireString(request.inviteId, "inviteId");

  const ref = db.doc(`invites/${inviteId}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "招待リンクが見つかりません。");
    }
    const invite = snapshot.data();
    if (invite.invitedBy !== uid) {
      const calendarSnapshot = await transaction.get(
        db.doc(`calendars/${invite.calendarId}`),
      );
      const owner = calendarSnapshot.exists ?
        ownerIdOf(calendarSnapshot.data()) :
        null;
      if (owner !== uid) {
        throw new HttpsError(
          "permission-denied",
          "招待リンクを取り消せるのは発行者本人とオーナーだけです。",
        );
      }
    }
    transaction.update(ref, {revoked: true, updatedAt: serverTimestamp()});
  });
}

/**
 * カレンダーの招待リンク一覧（メンバーなら誰でも）。
 *
 * `invites` はクライアントから read できないため、取り消し導線の一覧はここで返す。
 * トークンのハッシュは返さない（発行後にトークン本体を再表示する手段は無い）。
 *
 * @param {object} db Firestore。
 * @param {{uid: ?string, calendarId: *}} request 呼び出し元と引数。
 * @param {{now?: function(): Date}} deps テスト用。
 * @return {Promise<{invites: Array<object>}>}
 */
async function listInvites(db, request, deps = {}) {
  const uid = requireUid(request.uid);
  const calendarId = requireString(request.calendarId, "calendarId");
  const nowMs = (deps.now || (() => new Date()))().getTime();

  const calendarSnapshot = await db.doc(`calendars/${calendarId}`).get();
  if (!calendarSnapshot.exists) {
    throw new HttpsError("not-found", "カレンダーが見つかりません。");
  }
  if (!(calendarSnapshot.data().memberIds || []).includes(uid)) {
    throw new HttpsError(
      "permission-denied",
      "招待リンクを参照できるのはカレンダーのメンバーだけです。",
    );
  }

  const found = await db
    .collection("invites")
    .where("calendarId", "==", calendarId)
    .get();

  const invites = found.docs.map((doc) => {
    const invite = doc.data();
    const expiresAtMs = toMillis(invite.expiresAt);
    const maxUses = invite.maxUses || DEFAULT_MAX_USES;
    const usedCount = invite.usedCount || 0;
    return {
      id: doc.id,
      invitedBy: invite.invitedBy,
      expiresAt: new Date(expiresAtMs).toISOString(),
      maxUses,
      usedCount,
      revoked: Boolean(invite.revoked),
      active: !invite.revoked && expiresAtMs > nowMs && usedCount < maxUses,
    };
  });
  // 新しい順。orderBy を使わないのは複合インデックスを増やさないため。
  invites.sort((a, b) => b.expiresAt.localeCompare(a.expiresAt));
  return {invites};
}

module.exports = {
  DEFAULT_EXPIRES_IN_MS,
  DEFAULT_MAX_USES,
  acceptInvite,
  createInvite,
  generateToken,
  hashToken,
  listInvites,
  previewInvite,
  revokeInvite,
};

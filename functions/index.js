"use strict";

const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {beforeUserCreated} = require("firebase-functions/v2/identity");
const {onCall, onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");

const {handleBeforeCreate} = require("./handlers");
const api = require("./api");
const deleteaccount = require("./deleteaccount");
const invites = require("./invites");
const membership = require("./membership");
const notifications = require("./notifications");
const reminders = require("./reminders");

admin.initializeApp();
setGlobalOptions({region: "asia-northeast1"});

const serverTimestamp = () => FieldValue.serverTimestamp();

// 認証 Blocking Function（基本設計 §2.1）。
// アカウント作成時に users/{uid} と、本人だけが参加する個人カレンダーを生成する。
exports.beforefamilymembercreated = beforeUserCreated(async (event) => {
  await handleBeforeCreate(
    event,
    admin.firestore(),
    serverTimestamp,
    randomUUID,
  );
});

// カレンダーのメンバー管理（FR-8 / Issue #89）。memberIds / ownerId は Security
// Rules でクライアントから書けないため、変更経路はこの Callable のみ。
// 関数名は 2nd gen の制約に合わせて小文字（クライアントの呼び出し名と一致させる）。
exports.removemember = onCall(async (request) => {
  await membership.removeMember(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      calendarId: request.data && request.data.calendarId,
      targetUid: request.data && request.data.targetUid,
    },
    serverTimestamp,
  );
});

exports.leavecalendar = onCall(async (request) => {
  await membership.leaveCalendar(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      calendarId: request.data && request.data.calendarId,
    },
    serverTimestamp,
  );
});

exports.transferownership = onCall(async (request) => {
  await membership.transferOwnership(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      calendarId: request.data && request.data.calendarId,
      targetUid: request.data && request.data.targetUid,
    },
    serverTimestamp,
  );
});

// カレンダーの削除（Issue #169）。`firestore.rules` に `allow delete` は無く、
// 配下の `events` のカスケード削除も必要なため、削除経路はこの Callable のみ。
exports.deletecalendar = onCall(async (request) => {
  await membership.deleteCalendar(admin.firestore(), {
    uid: request.auth && request.auth.uid,
    calendarId: request.data && request.data.calendarId,
  });
});

// アカウント削除（退会導線、Issue #102）。Auth ユーザーの削除・他人のカレンダーの
// 更新・関連データの整理は Security Rules では行えないため、退会処理はこの Callable
// （Admin SDK）に一本化する。削除対象は常に呼び出し元本人（`request.auth.uid`）。
// 関数名は 2nd gen の制約に合わせて小文字（クライアントの呼び出し名と一致させる）。
exports.deleteaccount = onCall(async (request) => {
  await deleteaccount.deleteAccount(
    admin.firestore(),
    admin.auth(),
    {uid: request.auth && request.auth.uid},
    serverTimestamp,
  );
});

// 招待リンク（FR-9 / Issue #90）。`invites` はクライアントから read/write 全面禁止
// のため（`firestore.rules`）、発行・確認・受諾・取り消し・一覧の経路はこの
// Callable のみ。関数名は 2nd gen の制約に合わせて小文字。
exports.createinvite = onCall(async (request) => {
  return invites.createInvite(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      calendarId: request.data && request.data.calendarId,
    },
    serverTimestamp,
  );
});

exports.previewinvite = onCall(async (request) => {
  return invites.previewInvite(admin.firestore(), {
    uid: request.auth && request.auth.uid,
    token: request.data && request.data.token,
  });
});

exports.acceptinvite = onCall(async (request) => {
  return invites.acceptInvite(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      token: request.data && request.data.token,
    },
    serverTimestamp,
  );
});

exports.revokeinvite = onCall(async (request) => {
  await invites.revokeInvite(
    admin.firestore(),
    {
      uid: request.auth && request.auth.uid,
      inviteId: request.data && request.data.inviteId,
    },
    serverTimestamp,
  );
});

exports.listinvites = onCall(async (request) => {
  return invites.listInvites(admin.firestore(), {
    uid: request.auth && request.auth.uid,
    calendarId: request.data && request.data.calendarId,
  });
});

// 外部向け読み取り専用 REST API（Issue #103）。GAS・Home Assistant・MCP など
// 本人のスクリプトから予定を参照するための HTTP エンドポイント。認証は既存の
// サインインで得られる Firebase ID トークン（`Authorization: Bearer ...`）。
// CORS 設定はハンドラ側で自前に持つため onRequest の cors は無効にする。
// 関数名は 2nd gen の制約に合わせて小文字。仕様は docs/api.md。
//
// 公開 URL は Cloudflare Worker（`cloudflare/api-proxy/`）に一本化し、この
// `*.cloudfunctions.net` を直接叩く経路は共有シークレット `API_PROXY_KEY` で
// 塞ぐ。鍵は Secret Manager に置き、Worker 側にも同じ値を設定する。
const apiProxyKey = defineSecret("API_PROXY_KEY");

exports.api = onRequest(
  {cors: false, secrets: [apiProxyKey]},
  api.createApiHandler({db: admin.firestore(), auth: admin.auth()}),
);

const reminderDeps = {now: () => new Date(), newId: randomUUID};

// リマインド（FR-5 / 基本設計 §5.1、Issue #14）。関数名は 2nd gen の制約に
// 合わせて小文字（仕様上の名前は onEventWrite / sendDueReminders）。

// 予定の書き込みごとに (1) reminders を再生成し（旧分破棄 → triggerAt 再計算、
// Issue #14）、(2) 追加/変更/削除を同カレンダー参加者（操作者除く）へ共有通知する
// （Issue #77）。どちらも events/{id} の onWrite が契機のため 1 つの関数にまとめる。
exports.oneventwrite = onDocumentWritten("events/{eventId}", async (event) => {
  const before = event.data && event.data.before;
  const after = event.data && event.data.after;
  const change = {
    eventId: event.params.eventId,
    before: before && before.exists ? before.data() : null,
    after: after && after.exists ? after.data() : null,
  };

  await reminders.syncEventReminders(admin.firestore(), change, reminderDeps);
  await notifications.notifyEventChange(
    admin.firestore(),
    getMessaging(),
    change,
    {now: () => new Date()},
  );
});

// 毎分、配信時刻が到来した reminders を、設定した本人の全デバイスへ FCM 送信する。
exports.sendduereminders = onSchedule("every 1 minutes", async () => {
  await reminders.sendDueReminders(
    admin.firestore(),
    getMessaging(),
    reminderDeps,
  );
});

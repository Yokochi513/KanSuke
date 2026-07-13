"use strict";

const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const {beforeUserCreated} = require("firebase-functions/v2/identity");
const {onCall} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");

const {handleBeforeCreate} = require("./handlers");
const membership = require("./membership");

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

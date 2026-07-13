"use strict";

const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const {beforeUserCreated} = require("firebase-functions/v2/identity");
const {setGlobalOptions} = require("firebase-functions/v2");

const {handleBeforeCreate} = require("./handlers");

admin.initializeApp();
setGlobalOptions({region: "asia-northeast1"});

// 認証 Blocking Function（基本設計 §2.1）。
// アカウント作成時に users/{uid} と、本人だけが参加する個人カレンダーを生成する。
exports.beforefamilymembercreated = beforeUserCreated(async (event) => {
  await handleBeforeCreate(
    event,
    admin.firestore(),
    () => FieldValue.serverTimestamp(),
    randomUUID,
  );
});

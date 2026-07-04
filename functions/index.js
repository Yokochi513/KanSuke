"use strict";

const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const {beforeUserCreated} = require("firebase-functions/v2/identity");
const {setGlobalOptions} = require("firebase-functions/v2");

const {handleBeforeCreate} = require("./handlers");

admin.initializeApp();
setGlobalOptions({region: "asia-northeast1"});

// 認証 Blocking Function（基本設計 §2.1）。
// サインアップ時に家族 allowlist を照合し、対象外は拒否、
// 許可ユーザーは初回に users/{uid} を生成する。
exports.beforefamilymembercreated = beforeUserCreated((event) => {
  return handleBeforeCreate(
    event,
    admin.firestore(),
    () => FieldValue.serverTimestamp(),
  );
});

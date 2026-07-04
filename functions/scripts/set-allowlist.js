"use strict";

// 家族 allowlist の投入スクリプト（管理者用）。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 実行:
//        node scripts/set-allowlist.js <email> <name> <color(#RRGGBB)>
//   例:
//        node scripts/set-allowlist.js mom@example.com ママ "#D84315"
//
// allowlist/{email} に {name, color} を登録する。以後、そのメールでの
// サインアップのみ Blocking Function が許可する（基本設計 §2.1）。

const admin = require("firebase-admin");

async function main() {
  const [email, name, color] = process.argv.slice(2);
  if (!email || !name || !color) {
    console.error(
      "usage: node scripts/set-allowlist.js <email> <name> <color(#RRGGBB)>",
    );
    process.exit(1);
  }

  admin.initializeApp();
  const key = email.trim().toLowerCase();
  await admin.firestore().doc(`allowlist/${key}`).set({name, color});
  console.log(`registered allowlist/${key}`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

"use strict";

// 既存の `users/{uid}` から `email` フィールドを削除するスクリプト（管理者用、Issue #183）。
//
// 背景: `users/{uid}` は Security Rules 上「uid を知っている認証済みユーザーなら誰でも
// get できる」（列挙のみ禁止、NFR-4 / Issue #89）。同じカレンダーに一度でも同席すれば
// memberIds から uid を入手できるため、email を保存していると退出後も恒久的に
// メールアドレスを読まれてしまう。表示にも Cloud Functions にも使っていないフィールド
// なので、Firestore からは削除する。メールアドレスの正典は Firebase Auth 側にあり、
// サーバーで必要になれば `admin.auth().getUser(uid)` で取得できる。
//
// 新規サインアップ分は `functions/signup.js` の `buildInitialProfile` が既に email を
// 書かない。このスクリプトはそれ以前に作られたドキュメントの後始末に当たる。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 実行:
//        node scripts/remove-user-email.js
//
// email を持つドキュメントにだけ削除を適用する。冪等なため何度実行してもよい
// （2 回目以降は対象 0 件で終了する）。

const admin = require("firebase-admin");

const BATCH_SIZE = 500;

async function main() {
  admin.initializeApp();
  const firestore = admin.firestore();

  const snapshot = await firestore.collection("users").get();
  const targets = snapshot.docs.filter((doc) => "email" in doc.data());

  if (targets.length === 0) {
    console.log("email を持つユーザーはありません。");
    return;
  }

  for (let offset = 0; offset < targets.length; offset += BATCH_SIZE) {
    const batch = firestore.batch();
    const chunk = targets.slice(offset, offset + BATCH_SIZE);
    for (const doc of chunk) {
      // updatedAt は触らない。表示に使う情報（name / color）は変わっておらず、
      // 更新時刻を動かすとクライアントに無意味な差分として伝わるため。
      batch.update(doc.ref, {email: admin.firestore.FieldValue.delete()});
    }
    await batch.commit();
    console.log(`${offset + chunk.length}/${targets.length} 件を更新しました。`);
  }

  console.log(`完了: ${targets.length} 件のユーザーから email を削除しました。`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

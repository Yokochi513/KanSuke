"use strict";

// 複数カレンダー機能（FR-8）導入前に作成された予定へ calendarId を
// 埋め込むバックフィルスクリプト（管理者用、1回だけ実行する）。
//
// 背景: Firestore の等価フィルタは「フィールドが存在しない」ドキュメントに
// マッチしないため、calendarId 未設定の既存予定を安全な絞り込みクエリ
// （firestore.rules が要求する where('calendarId','==',...)）で拾うことが
// できない。Admin SDK は Security Rules を経由しないため、フィールド欠損の
// クエリ制約を受けずに全件スキャンしてバックフィルできる。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 実行（firestore.rules・firestore.indexes.json のデプロイより前に
//      実行しておくこと。順序を守れば calendarId 欠損の予定が新ルール適用の
//      瞬間にも視界から消えない）:
//        node scripts/backfill-event-calendar-id.js
//
// calendarId が存在しない events ドキュメントにだけ calendarId: 'default'
// を設定する。既に calendarId が設定済みのドキュメントには触れない。

const admin = require("firebase-admin");

const BATCH_SIZE = 500;

async function main() {
  admin.initializeApp();
  const firestore = admin.firestore();

  const snapshot = await firestore.collection("events").get();
  const targets = snapshot.docs.filter((doc) => !("calendarId" in doc.data()));

  if (targets.length === 0) {
    console.log("calendarId 未設定の予定はありません。");
    return;
  }

  for (let offset = 0; offset < targets.length; offset += BATCH_SIZE) {
    const batch = firestore.batch();
    const chunk = targets.slice(offset, offset + BATCH_SIZE);
    for (const doc of chunk) {
      batch.update(doc.ref, {calendarId: "default"});
    }
    await batch.commit();
    console.log(`${offset + chunk.length}/${targets.length} 件を更新しました。`);
  }

  console.log(`完了: ${targets.length} 件の予定に calendarId: 'default' を設定しました。`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

"use strict";

// カレンダー権限モデル（Issue #89）導入前に作成された calendars へ ownerId を
// 埋め込むバックフィルスクリプト（管理者用、1回だけ実行する）。
//
// 背景: オーナー（ownerId）はカレンダー名の変更・メンバー削除・オーナー移譲を
// できる唯一のメンバー。導入前のカレンダーには ownerId が存在しないため、作成者
// （creatorId）をオーナーとしてバックフィルする。Security Rules と Callable
// Function は ownerId 欠損時に creatorId へフォールバックするため（後方互換）、
// このスクリプトはフォールバックを不要にするための後始末に当たる。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 実行（旧・既定カレンダー 'default' も対象に含まれる）:
//        node scripts/backfill-calendar-owner-id.js
//
// ownerId が存在しない calendars ドキュメントにだけ ownerId: creatorId を設定する。
// 既に ownerId が設定済みのドキュメントには触れない。

const admin = require("firebase-admin");

const BATCH_SIZE = 500;

async function main() {
  admin.initializeApp();
  const firestore = admin.firestore();

  const snapshot = await firestore.collection("calendars").get();
  const targets = snapshot.docs.filter((doc) => !("ownerId" in doc.data()));
  const orphans = targets.filter((doc) => !doc.data().creatorId);

  if (orphans.length > 0) {
    // creatorId が無いカレンダーはオーナーを決められない。手当てが必要なため中断する。
    const ids = orphans.map((doc) => doc.id).join(", ");
    throw new Error(`creatorId が無いカレンダーがあります: ${ids}`);
  }

  if (targets.length === 0) {
    console.log("ownerId 未設定のカレンダーはありません。");
    return;
  }

  for (let offset = 0; offset < targets.length; offset += BATCH_SIZE) {
    const batch = firestore.batch();
    const chunk = targets.slice(offset, offset + BATCH_SIZE);
    for (const doc of chunk) {
      batch.update(doc.ref, {ownerId: doc.data().creatorId});
    }
    await batch.commit();
    console.log(`${offset + chunk.length}/${targets.length} 件を更新しました。`);
  }

  console.log(`完了: ${targets.length} 件のカレンダーに ownerId を設定しました。`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

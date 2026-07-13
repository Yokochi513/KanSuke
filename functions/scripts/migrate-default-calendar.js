"use strict";

// 旧・既定カレンダー（固定 ID `calendars/default`）を UUID のカレンダーへ移行する
// スクリプト（管理者用、1回だけ実行する。Issue #93）。
//
// 背景: カレンダーのドキュメント ID は UUID で統一されている（アプリ側はクライアント
// 生成、個人カレンダーは Auth Blocking Function が生成）。複数カレンダー機能（FR-8）の
// 導入時に作られた旧・既定カレンダーだけが固定 ID 'default' の例外として残っており、
// これを解消して Security Rules / モデルの後方互換フォールバックを撤去する。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 事前確認（既定はドライラン。書き込みはせず、対象の有無と件数だけを表示する）:
//        node scripts/migrate-default-calendar.js
//   3. 移行の実行（firestore.rules のデプロイより前に実行すること。順序を誤ると、
//      移行途中の予定が一時的に誰からも見えなくなる）:
//        node scripts/migrate-default-calendar.js --apply
//
// 移行内容:
//   1. calendars/default の内容を新しい UUID のドキュメントへコピーする。
//   2. calendarId == 'default' の全 events を新しい UUID へ書き換える。
//   3. calendars/default を削除する。
//
// events の書き換えが終わるまで calendars/default は存在し続けるため、移行中も
// 予定はメンバーから見え続ける。
//
// 旧・既定カレンダーも calendarId == 'default' の予定も存在しなければ、移行は不要で
// コード側のフォールバック撤去だけで足りる。

const crypto = require("node:crypto");
const admin = require("firebase-admin");

const LEGACY_CALENDAR_ID = "default";
const BATCH_SIZE = 500;

async function main() {
  const apply = process.argv.includes("--apply");

  const app = admin.initializeApp();
  const projectId = app.options.projectId || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    // 接続先が解決できないまま実行すると、空のプロジェクトを見て「対象 0 件」と
    // 誤報告しうる。その 0 件を信じて Rules をデプロイすると、calendarId が
    // 'default' のままの予定が誰からも読めなくなるため、ここで中断する。
    throw new Error(
      "接続先プロジェクトを特定できません。GOOGLE_APPLICATION_CREDENTIALS と " +
      "GOOGLE_CLOUD_PROJECT を設定してください。",
    );
  }
  console.log(`接続先プロジェクト: ${projectId}`);

  const firestore = admin.firestore();

  const calendars = await firestore.collection("calendars").get();
  if (calendars.empty) {
    // 個人カレンダーはアカウント作成時に必ず作られる。1件も無いのは空の
    // プロジェクトを見ている証拠なので、誤った「対象 0 件」を出す前に止める。
    throw new Error(
      `${projectId} には calendars が1件もありません。接続先が誤っています。`,
    );
  }
  console.log(`calendars: ${calendars.size} 件`);

  const legacyRef = firestore.collection("calendars").doc(LEGACY_CALENDAR_ID);
  const legacyCalendar = await legacyRef.get();
  const events = await firestore
    .collection("events")
    .where("calendarId", "==", LEGACY_CALENDAR_ID)
    .get();

  const existence = legacyCalendar.exists ? "存在する" : "存在しない";
  console.log(`calendars/${LEGACY_CALENDAR_ID}: ${existence}`);
  console.log(`calendarId が '${LEGACY_CALENDAR_ID}' の予定: ${events.size} 件`);

  if (!legacyCalendar.exists && events.empty) {
    console.log("移行は不要です（コード側のフォールバック撤去だけで足ります）。");
    return;
  }

  if (!legacyCalendar.exists) {
    // 移行先カレンダーの名前・メンバーを決められないため、手当てが必要。
    throw new Error(
      `calendars/${LEGACY_CALENDAR_ID} が存在しないのに、` +
      `calendarId が '${LEGACY_CALENDAR_ID}' の予定が ${events.size} 件あります。`,
    );
  }

  if (!apply) {
    console.log("ドライランのため書き込みは行いません。実行するには --apply を付けてください。");
    return;
  }

  const newCalendarId = crypto.randomUUID();
  await firestore.collection("calendars").doc(newCalendarId).set(legacyCalendar.data());
  console.log(`calendars/${newCalendarId} を作成しました（旧・既定カレンダーの複製）。`);

  const targets = events.docs;
  for (let offset = 0; offset < targets.length; offset += BATCH_SIZE) {
    const batch = firestore.batch();
    const chunk = targets.slice(offset, offset + BATCH_SIZE);
    for (const doc of chunk) {
      batch.update(doc.ref, {calendarId: newCalendarId});
    }
    await batch.commit();
    console.log(`${offset + chunk.length}/${targets.length} 件の予定を更新しました。`);
  }

  await legacyRef.delete();
  console.log(`calendars/${LEGACY_CALENDAR_ID} を削除しました。`);
  console.log(`完了: ${targets.length} 件の予定を calendars/${newCalendarId} へ移行しました。`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

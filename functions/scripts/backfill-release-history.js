"use strict";

// 更新履歴（Issue #96）の導入前に公開された過去バージョンを、CHANGELOG.md から
// releases/{version} へ流し込むバックフィルスクリプト（管理者用、1回だけ実行する）。
//
// 背景: これまで CI（scripts/publish-release-version.js）は meta/release に最新
// 1 バージョンしか書いていなかったため、過去のリリースノートが Firestore に無い。
// CHANGELOG.md の `## [x.y.z] - YYYY-MM-DD` セクションを正として全件を書き込む。
// 以降のリリースは CI が releases/{version} も更新するため、本スクリプトは不要。
//
// 使い方:
//   1. 管理者権限のサービスアカウント鍵を用意し、環境変数を設定する:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//        export GOOGLE_CLOUD_PROJECT=<firebase-project-id>
//   2. 実行（リポジトリのルートから）:
//        node functions/scripts/backfill-release-history.js
//
// ドキュメント ID がバージョンのため、複数回実行しても履歴は重複しない。既に
// publishedAt を持つドキュメントには触れない（CI が書いた公開日時を上書きしない）。

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// `## [1.3.0] - 2026-07-13` から次の見出しまでを 1 リリースとして切り出す。
// 日付を持たない `## [Unreleased]` は未公開のため対象外。
function readReleases() {
  const changelog = fs.readFileSync(
    path.join(REPO_ROOT, "CHANGELOG.md"),
    "utf8",
  );
  const sectionRegex =
    /##\s*\[(\d+(?:\.\d+)*)\]\s*-\s*(\d{4}-\d{2}-\d{2})\s*\n([\s\S]*?)(?=\n##\s|$)/g;

  const releases = [];
  for (const match of changelog.matchAll(sectionRegex)) {
    releases.push({
      version: match[1],
      publishedAt: new Date(`${match[2]}T00:00:00Z`),
      notes: match[3].trim(),
    });
  }
  return releases;
}

async function main() {
  const releases = readReleases();
  if (releases.length === 0) {
    throw new Error("CHANGELOG.md から公開済みバージョンを読み取れませんでした");
  }

  admin.initializeApp();
  const firestore = admin.firestore();
  const collection = firestore.collection("releases");

  let written = 0;
  for (const release of releases) {
    const docRef = collection.doc(release.version);
    const current = await docRef.get();
    if (current.exists && current.data().publishedAt) {
      console.log(`releases/${release.version} は既にあります。スキップします。`);
      continue;
    }
    await docRef.set({
      version: release.version,
      notes: release.notes,
      publishedAt: admin.firestore.Timestamp.fromDate(release.publishedAt),
    });
    written += 1;
    console.log(`releases/${release.version} を書き込みました。`);
  }

  console.log(
    `完了: ${releases.length} 件中 ${written} 件を releases へ書き込みました。`,
  );
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

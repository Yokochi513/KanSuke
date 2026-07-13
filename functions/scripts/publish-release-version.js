"use strict";

// リリース時にアプリの最新バージョン情報を Firestore へ反映するスクリプト（FR-7）。
//
// main への push（develop → main のリリースマージ）をトリガーに GitHub Actions
// (.github/workflows/publish-release-version.yml) から実行される。
//
// 手動実行する場合:
//   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//   node functions/scripts/publish-release-version.js
//
// pubspec.yaml の version と CHANGELOG.md の該当セクションを読み取り、
// 次の 2 つへ反映する（Issue #96）。
//   - meta/release       … 起動時のお知らせ用の最新 1 件。バージョンが変化して
//                          いない場合は更新しない（無用な通知の再発火を避ける）。
//   - releases/{version} … 設定画面の更新履歴用。ドキュメント ID がバージョンの
//                          ため、同じバージョンを再度 publish しても重複しない
//                          （publishedAt は初回の値を保つ）。

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

function readPubspecVersion() {
  const pubspec = fs.readFileSync(
    path.join(REPO_ROOT, "pubspec.yaml"),
    "utf8",
  );
  const match = pubspec.match(/^version:\s*([^\s+]+)/m);
  if (!match) {
    throw new Error("pubspec.yaml に version が見つかりません");
  }
  return match[1];
}

function readReleaseNotes(version) {
  const changelogPath = path.join(REPO_ROOT, "CHANGELOG.md");
  if (!fs.existsSync(changelogPath)) {
    console.warn("CHANGELOG.md が見つかりません。notes は空にします。");
    return "";
  }
  const changelog = fs.readFileSync(changelogPath, "utf8");
  const escaped = version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const sectionRegex = new RegExp(
    `##\\s*\\[${escaped}\\][^\\n]*\\n([\\s\\S]*?)(?=\\n##\\s*\\[|$)`,
  );
  const match = changelog.match(sectionRegex);
  if (!match) {
    console.warn(
      `CHANGELOG.md に [${version}] セクションが見つかりません。notes は空にします。`,
    );
    return "";
  }
  return match[1].trim();
}

async function main() {
  const version = readPubspecVersion();
  const notes = readReleaseNotes(version);

  admin.initializeApp();
  const firestore = admin.firestore();

  await publishHistory(firestore, version, notes);
  await publishLatest(firestore, version, notes);
}

// 更新履歴（releases/{version}）へ書き込む。既にある場合は notes だけ上書きし、
// publishedAt は初回の公開日時を保つ。
async function publishHistory(firestore, version, notes) {
  const docRef = firestore.collection("releases").doc(version);
  const current = await docRef.get();
  const publishedAt = current.exists && current.data().publishedAt
    ? current.data().publishedAt
    : admin.firestore.FieldValue.serverTimestamp();

  await docRef.set({version, notes, publishedAt});
  console.log(`releases/${version} を更新しました。`);
}

// 起動時のお知らせ用の最新 1 件（meta/release）を更新する。
async function publishLatest(firestore, version, notes) {
  const docRef = firestore.doc("meta/release");
  const current = await docRef.get();

  if (current.exists && current.data().version === version) {
    console.log(`meta/release は既に version=${version} のため更新しません。`);
    return;
  }

  await docRef.set({
    version,
    notes,
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`meta/release を version=${version} に更新しました。`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

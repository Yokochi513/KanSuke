"use strict";

const assert = require("node:assert");
const {evaluateSignup} = require("../allowlist");
const {handleBeforeCreate} = require("../handlers");

// Firestore を模した最小フェイク。書き込みを writes に記録する。
function fakeDb(docs) {
  const writes = {};
  return {
    writes,
    doc(path) {
      return {
        async get() {
          return {
            exists: Object.prototype.hasOwnProperty.call(docs, path),
            data: () => docs[path],
          };
        },
        async set(data) {
          writes[path] = data;
        },
      };
    },
  };
}

describe("evaluateSignup", function() {
  it("allowlist に存在すれば許可し user 情報を返す", function() {
    const result = evaluateSignup("mom@example.com", {
      name: "ママ",
      color: "#D84315",
    });
    assert.strictEqual(result.allowed, true);
    assert.deepStrictEqual(result.user, {
      email: "mom@example.com",
      name: "ママ",
      color: "#D84315",
    });
  });

  it("allowlist に無ければ拒否する", function() {
    assert.strictEqual(evaluateSignup("x@example.com", null).allowed, false);
  });
});

describe("handleBeforeCreate", function() {
  const serverTimestamp = () => "SERVER_TS";

  it("allowlist 外は拒否し users を作らない", async function() {
    const db = fakeDb({});
    await assert.rejects(
      () =>
        handleBeforeCreate(
          {data: {email: "x@example.com", uid: "u1"}},
          db,
          serverTimestamp,
        ),
      /利用権限がありません/,
    );
    assert.deepStrictEqual(db.writes, {});
  });

  it("許可ユーザーは users/{uid} を allowlist 情報で生成する", async function() {
    const db = fakeDb({
      "allowlist/mom@example.com": {name: "ママ", color: "#D84315"},
    });
    // 大文字メールでも正規化して照合できること。
    await handleBeforeCreate(
      {data: {email: "Mom@Example.com", uid: "u1"}},
      db,
      serverTimestamp,
    );
    assert.deepStrictEqual(db.writes["users/u1"], {
      name: "ママ",
      email: "mom@example.com",
      color: "#D84315",
      createdAt: "SERVER_TS",
      updatedAt: "SERVER_TS",
    });
  });
});

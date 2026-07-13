"use strict";

const assert = require("node:assert");
const {buildInitialProfile, memberColors} = require("../signup");
const {handleBeforeCreate} = require("../handlers");

// Firestore を模した最小フェイク。書き込みを writes に記録する。
function fakeDb() {
  const writes = {};
  return {
    writes,
    doc(path) {
      return {
        async set(data) {
          writes[path] = data;
        },
      };
    },
  };
}

describe("buildInitialProfile", function() {
  it("表示名とメールを正規化し、識別色を割り当てる", function() {
    const profile = buildInitialProfile({
      uid: "u1",
      email: "Mom@Example.com ",
      displayName: "ママ",
    });
    assert.strictEqual(profile.name, "ママ");
    assert.strictEqual(profile.email, "mom@example.com");
    assert.ok(memberColors.includes(profile.color));
  });

  it("表示名が無ければメールのローカル部を名前にする", function() {
    const profile = buildInitialProfile({uid: "u1", email: "dad@example.com"});
    assert.strictEqual(profile.name, "dad");
  });

  it("表示名もメールも無ければ既定の名前にする", function() {
    const profile = buildInitialProfile({uid: "u1"});
    assert.strictEqual(profile.name, "メンバー");
    assert.strictEqual(profile.email, "");
  });

  it("同じ uid には同じ識別色を割り当てる", function() {
    const first = buildInitialProfile({uid: "u1", email: "a@example.com"});
    const second = buildInitialProfile({uid: "u1", email: "a@example.com"});
    assert.strictEqual(first.color, second.color);
  });
});

describe("handleBeforeCreate", function() {
  const serverTimestamp = () => "SERVER_TS";
  const newId = () => "calendar-uuid";

  it("users/{uid} を ID プロバイダの情報から生成する", async function() {
    const db = fakeDb();
    await handleBeforeCreate(
      {data: {email: "Mom@Example.com", uid: "u1", displayName: "ママ"}},
      db,
      serverTimestamp,
      newId,
    );
    assert.deepStrictEqual(db.writes["users/u1"], {
      name: "ママ",
      email: "mom@example.com",
      color: buildInitialProfile({uid: "u1"}).color,
      createdAt: "SERVER_TS",
      updatedAt: "SERVER_TS",
    });
  });

  it("本人がオーナーの個人カレンダーを生成する（FR-8 / Issue #89）", async function() {
    const db = fakeDb();
    const result = await handleBeforeCreate(
      {data: {email: "mom@example.com", uid: "u1", displayName: "ママ"}},
      db,
      serverTimestamp,
      newId,
    );
    assert.strictEqual(result.calendarId, "calendar-uuid");
    assert.deepStrictEqual(db.writes["calendars/calendar-uuid"], {
      name: "ママのカレンダー",
      memberIds: ["u1"],
      creatorId: "u1",
      ownerId: "u1",
      createdAt: "SERVER_TS",
      updatedAt: "SERVER_TS",
    });
  });

  it("誰のサインアップも拒否しない（allowlist 廃止）", async function() {
    const db = fakeDb();
    await assert.doesNotReject(() =>
      handleBeforeCreate(
        {data: {email: "stranger@example.com", uid: "u2"}},
        db,
        serverTimestamp,
        newId,
      ),
    );
    assert.ok(db.writes["users/u2"]);
    assert.deepStrictEqual(
      db.writes["calendars/calendar-uuid"].memberIds,
      ["u2"],
    );
  });
});

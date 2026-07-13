"use strict";

const assert = require("node:assert");
const {
  leaveCalendar,
  removeMember,
  transferOwnership,
} = require("../membership");

const serverTimestamp = () => "SERVER_TS";

// Firestore のトランザクションを模した最小フェイク。
// calendars/{id} のデータを保持し、update をその場で反映する。
function fakeDb(calendars) {
  const store = {...calendars};
  return {
    store,
    doc(path) {
      return {path};
    },
    async runTransaction(body) {
      return body({
        async get(ref) {
          const data = store[ref.path];
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
        update(ref, patch) {
          store[ref.path] = {...store[ref.path], ...patch};
        },
      });
    },
  };
}

function shared(overrides = {}) {
  return fakeDb({
    "calendars/shared": {
      name: "わが家",
      memberIds: ["owner", "member"],
      creatorId: "owner",
      ownerId: "owner",
      ...overrides,
    },
  });
}

async function assertHttpsError(code, run) {
  await assert.rejects(run, (error) => {
    assert.strictEqual(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

describe("removeMember（Issue #89）", function() {
  it("オーナーはメンバーを削除できる", async function() {
    const db = shared();

    await removeMember(
      db,
      {uid: "owner", calendarId: "shared", targetUid: "member"},
      serverTimestamp,
    );

    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, ["owner"]);
    assert.strictEqual(db.store["calendars/shared"].updatedAt, "SERVER_TS");
  });

  it("メンバーが呼ぶと permission-denied になる", async function() {
    const db = shared();

    await assertHttpsError("permission-denied", () => removeMember(
      db,
      {uid: "member", calendarId: "shared", targetUid: "owner"},
      serverTimestamp,
    ));
    assert.deepStrictEqual(
      db.store["calendars/shared"].memberIds,
      ["owner", "member"],
    );
  });

  it("オーナー自身は削除できない", async function() {
    const db = shared();

    await assertHttpsError("failed-precondition", () => removeMember(
      db,
      {uid: "owner", calendarId: "shared", targetUid: "owner"},
      serverTimestamp,
    ));
  });

  it("参加していないメンバーは削除できない", async function() {
    const db = shared();

    await assertHttpsError("failed-precondition", () => removeMember(
      db,
      {uid: "owner", calendarId: "shared", targetUid: "outsider"},
      serverTimestamp,
    ));
  });

  it("ownerId 欠損時は creatorId をオーナーとみなす（バックフィル前の後方互換）",
    async function() {
      const db = shared({ownerId: undefined});

      await removeMember(
        db,
        {uid: "owner", calendarId: "shared", targetUid: "member"},
        serverTimestamp,
      );

      assert.deepStrictEqual(db.store["calendars/shared"].memberIds, ["owner"]);
    });

  it("未サインインは unauthenticated になる", async function() {
    await assertHttpsError("unauthenticated", () => removeMember(
      shared(),
      {uid: null, calendarId: "shared", targetUid: "member"},
      serverTimestamp,
    ));
  });

  it("引数が欠けていれば invalid-argument になる", async function() {
    await assertHttpsError("invalid-argument", () => removeMember(
      shared(),
      {uid: "owner", calendarId: "shared"},
      serverTimestamp,
    ));
  });

  it("存在しないカレンダーは not-found になる", async function() {
    await assertHttpsError("not-found", () => removeMember(
      shared(),
      {uid: "owner", calendarId: "missing", targetUid: "member"},
      serverTimestamp,
    ));
  });
});

describe("leaveCalendar（Issue #89）", function() {
  it("メンバーは自分だけを退出させられる", async function() {
    const db = shared();

    await leaveCalendar(
      db,
      {uid: "member", calendarId: "shared"},
      serverTimestamp,
    );

    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, ["owner"]);
  });

  it("オーナーは移譲しない限り退出できない", async function() {
    const db = shared();

    await assertHttpsError("failed-precondition", () => leaveCalendar(
      db,
      {uid: "owner", calendarId: "shared"},
      serverTimestamp,
    ));
    assert.deepStrictEqual(
      db.store["calendars/shared"].memberIds,
      ["owner", "member"],
    );
  });

  it("最後の1人は退出できない（カレンダー削除機能が無いため）", async function() {
    const db = fakeDb({
      "calendars/solo": {
        name: "個人",
        memberIds: ["solo"],
        creatorId: "solo",
        ownerId: "solo",
      },
    });

    await assertHttpsError("failed-precondition", () => leaveCalendar(
      db,
      {uid: "solo", calendarId: "solo"},
      serverTimestamp,
    ));
  });

  it("参加していないカレンダーからは退出できない", async function() {
    await assertHttpsError("permission-denied", () => leaveCalendar(
      shared(),
      {uid: "outsider", calendarId: "shared"},
      serverTimestamp,
    ));
  });
});

describe("transferOwnership（Issue #89）", function() {
  it("オーナーを他のメンバーへ移譲できる", async function() {
    const db = shared();

    await transferOwnership(
      db,
      {uid: "owner", calendarId: "shared", targetUid: "member"},
      serverTimestamp,
    );

    assert.strictEqual(db.store["calendars/shared"].ownerId, "member");
    // 作成者は監査用に不変。
    assert.strictEqual(db.store["calendars/shared"].creatorId, "owner");
  });

  it("移譲後の元オーナーは退出できる", async function() {
    const db = shared();

    await transferOwnership(
      db,
      {uid: "owner", calendarId: "shared", targetUid: "member"},
      serverTimestamp,
    );
    await leaveCalendar(
      db,
      {uid: "owner", calendarId: "shared"},
      serverTimestamp,
    );

    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, ["member"]);
  });

  it("オーナー以外は移譲できない", async function() {
    await assertHttpsError("permission-denied", () => transferOwnership(
      shared(),
      {uid: "member", calendarId: "shared", targetUid: "member"},
      serverTimestamp,
    ));
  });

  it("メンバー以外へは移譲できない", async function() {
    await assertHttpsError("failed-precondition", () => transferOwnership(
      shared(),
      {uid: "owner", calendarId: "shared", targetUid: "outsider"},
      serverTimestamp,
    ));
  });
});

"use strict";

const assert = require("node:assert");
const {
  deleteCalendar,
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

// カレンダーの削除（Issue #169）用のフェイク。トランザクションではなく
// collection().where().limit().get() / batch() / doc().delete() を使うため、
// パス -> データのフラットな store で最小限に模す。
function fakeStoreDb(initial) {
  const store = {...initial};
  let failNextCommit = false;

  const docRef = (path) => ({
    path,
    id: path.split("/").pop(),
    async get() {
      const data = store[path];
      return {exists: data !== undefined, data: () => data};
    },
    async delete() {
      delete store[path];
    },
  });

  const matches = (path, filters) => filters.every(([field, value]) => {
    const stored = store[path][field];
    // array-contains と == を、格納されている値の形で見分けるだけの簡易実装。
    return Array.isArray(stored) ? stored.includes(value) : stored === value;
  });

  const query = (name, filters, max) => ({
    where(field, op, value) {
      return query(name, [...filters, [field, value]], max);
    },
    limit(n) {
      return query(name, filters, n);
    },
    async get() {
      const paths = Object.keys(store)
        .filter((path) => path.startsWith(`${name}/`))
        .filter((path) => matches(path, filters));
      const docs = (max === undefined ? paths : paths.slice(0, max))
        .map((path) => ({ref: docRef(path), data: () => store[path]}));
      return {docs};
    },
  });

  return {
    store,
    failCommitOnce() {
      failNextCommit = true;
    },
    doc: docRef,
    collection: (name) => query(name, [], undefined),
    batch() {
      const paths = [];
      return {
        delete(ref) {
          paths.push(ref.path);
        },
        async commit() {
          if (failNextCommit) {
            failNextCommit = false;
            throw new Error("commit failed");
          }
          for (const path of paths) delete store[path];
        },
      };
    },
  };
}

/** オーナー me が 2 つのカレンダー（削除対象 target と個人用 solo）を持つ状態。 */
function deletable(extra = {}) {
  return fakeStoreDb({
    "calendars/target": {
      name: "わが家",
      memberIds: ["me", "member"],
      creatorId: "me",
      ownerId: "me",
    },
    "calendars/solo": {
      name: "わたしのカレンダー",
      memberIds: ["me"],
      creatorId: "me",
      ownerId: "me",
    },
    "events/e1": {calendarId: "target", title: "夕食"},
    "events/e2": {calendarId: "target", title: "通院"},
    "events/other": {calendarId: "solo", title: "残るべき予定"},
    "invites/i1": {calendarId: "target", invitedBy: "me"},
    "invites/other": {calendarId: "solo", invitedBy: "me"},
    ...extra,
  });
}

describe("deleteCalendar（Issue #169）", function() {
  it("オーナーはカレンダーを予定・招待ごと削除できる", async function() {
    const db = deletable();

    await deleteCalendar(db, {uid: "me", calendarId: "target"});

    assert.strictEqual(db.store["calendars/target"], undefined);
    assert.strictEqual(db.store["events/e1"], undefined);
    assert.strictEqual(db.store["events/e2"], undefined);
    assert.strictEqual(db.store["invites/i1"], undefined);
    // 他のカレンダーとその予定・招待は残る。
    assert.ok(db.store["calendars/solo"]);
    assert.ok(db.store["events/other"]);
    assert.ok(db.store["invites/other"]);
  });

  it("オーナー以外は削除できない", async function() {
    const db = deletable();

    await assertHttpsError("permission-denied", () => deleteCalendar(
      db,
      {uid: "member", calendarId: "target"},
    ));
    assert.ok(db.store["calendars/target"]);
    assert.ok(db.store["events/e1"]);
  });

  it("参加カレンダーが 1 つだけなら削除できない", async function() {
    const db = fakeStoreDb({
      "calendars/solo": {
        name: "わたしのカレンダー",
        memberIds: ["me"],
        creatorId: "me",
        ownerId: "me",
      },
      "events/e1": {calendarId: "solo", title: "夕食"},
    });

    await assertHttpsError("failed-precondition", () => deleteCalendar(
      db,
      {uid: "me", calendarId: "solo"},
    ));
    assert.ok(db.store["calendars/solo"]);
    assert.ok(db.store["events/e1"]);
  });

  it("存在しないカレンダーは not-found", async function() {
    await assertHttpsError("not-found", () => deleteCalendar(
      deletable(),
      {uid: "me", calendarId: "missing"},
    ));
  });

  it("calendarId が無ければ invalid-argument", async function() {
    await assertHttpsError("invalid-argument", () => deleteCalendar(
      deletable(),
      {uid: "me"},
    ));
  });

  it("サインインしていなければ unauthenticated", async function() {
    await assertHttpsError("unauthenticated", () => deleteCalendar(
      deletable(),
      {uid: null, calendarId: "target"},
    ));
  });

  it("500 件を超える予定をバッチに分けて削除する", async function() {
    const events = {};
    for (let i = 0; i < 1200; i += 1) {
      events[`events/bulk${i}`] = {calendarId: "target", title: `予定${i}`};
    }
    const db = deletable(events);

    await deleteCalendar(db, {uid: "me", calendarId: "target"});

    const remaining = Object.keys(db.store)
      .filter((path) => path.startsWith("events/"))
      .filter((path) => db.store[path].calendarId === "target");
    assert.deepStrictEqual(remaining, []);
    assert.strictEqual(db.store["calendars/target"], undefined);
  });

  it("途中で失敗しても再実行すれば完了できる", async function() {
    const db = deletable();
    db.failCommitOnce();

    await assert.rejects(() => deleteCalendar(db, {
      uid: "me",
      calendarId: "target",
    }));
    // 本体を最後に消すため、失敗時点ではカレンダーが残っている。
    assert.ok(db.store["calendars/target"]);

    await deleteCalendar(db, {uid: "me", calendarId: "target"});

    assert.strictEqual(db.store["calendars/target"], undefined);
    assert.strictEqual(db.store["events/e1"], undefined);
    assert.strictEqual(db.store["invites/i1"], undefined);
  });
});

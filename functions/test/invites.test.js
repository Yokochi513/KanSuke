"use strict";

const assert = require("node:assert");
const {
  acceptInvite,
  createInvite,
  hashToken,
  listInvites,
  previewInvite,
  revokeInvite,
} = require("../invites");

const serverTimestamp = () => "SERVER_TS";
const now = new Date("2026-07-01T00:00:00Z");
const nowDeps = {now: () => now};

// Firestore（Admin SDK）の最小フェイク。パス → データの Map を保持し、
// ドキュメント取得・単純な where 一致クエリ・トランザクションを模す。
function fakeDb(seed) {
  const store = {...seed};
  let autoId = 0;

  const snapshotOf = (path) => ({
    exists: store[path] !== undefined,
    id: path.split("/").pop(),
    ref: docRef(path),
    data: () => store[path],
  });

  function docRef(path) {
    return {
      path,
      id: path.split("/").pop(),
      async get() {
        return snapshotOf(path);
      },
      async set(data) {
        store[path] = data;
      },
    };
  }

  function queryOf(name, conditions) {
    return {
      isQuery: true,
      limit() {
        return queryOf(name, conditions);
      },
      run() {
        const docs = Object.keys(store)
          .filter((path) => path.startsWith(`${name}/`))
          .filter((path) =>
            conditions.every(([field, value]) => store[path][field] === value),
          )
          .map(snapshotOf);
        return {empty: docs.length === 0, docs};
      },
      async get() {
        return this.run();
      },
    };
  }

  return {
    store,
    doc: docRef,
    collection(name) {
      return {
        doc(id) {
          autoId += 1;
          return docRef(`${name}/${id || `generated-${autoId}`}`);
        },
        where(field, _op, value) {
          return queryOf(name, [[field, value]]);
        },
      };
    },
    async runTransaction(body) {
      return body({
        async get(target) {
          return target.isQuery ? target.run() : target.get();
        },
        update(ref, patch) {
          store[ref.path] = {...store[ref.path], ...patch};
        },
      });
    },
  };
}

function invite(overrides = {}) {
  return {
    calendarId: "shared",
    tokenHash: hashToken("secret-token"),
    invitedBy: "member",
    expiresAt: new Date(now.getTime() + 60 * 60 * 1000),
    maxUses: 1,
    usedCount: 0,
    revoked: false,
    ...overrides,
  };
}

function seeded(inviteOverrides = {}, calendarOverrides = {}) {
  return fakeDb({
    "calendars/shared": {
      name: "わが家",
      memberIds: ["owner", "member"],
      creatorId: "owner",
      ownerId: "owner",
      ...calendarOverrides,
    },
    "users/member": {name: "母"},
    "users/owner": {name: "父"},
    "invites/invite-1": invite(inviteOverrides),
  });
}

async function assertHttpsError(code, run, reason) {
  await assert.rejects(run, (error) => {
    assert.strictEqual(error.code, code, `expected ${code}, got ${error.code}`);
    if (reason) {
      assert.strictEqual(error.details && error.details.reason, reason);
    }
    return true;
  });
}

describe("createInvite（Issue #90）", function() {
  it("メンバーは招待リンクを発行できる", async function() {
    const db = seeded();
    const result = await createInvite(
      db,
      {uid: "member", calendarId: "shared"},
      serverTimestamp,
      nowDeps,
    );

    assert.ok(result.token.length >= 32);
    const stored = db.store[`invites/${result.inviteId}`];
    assert.strictEqual(stored.calendarId, "shared");
    assert.strictEqual(stored.invitedBy, "member");
    assert.strictEqual(stored.maxUses, 1);
    assert.strictEqual(stored.usedCount, 0);
    assert.strictEqual(stored.revoked, false);
    // 既定の有効期限は 24 時間。
    assert.strictEqual(
      stored.expiresAt.getTime() - now.getTime(),
      24 * 60 * 60 * 1000,
    );
  });

  it("トークン本体は保存せず、ハッシュだけを保存する", async function() {
    const db = seeded();
    const result = await createInvite(
      db,
      {uid: "member", calendarId: "shared"},
      serverTimestamp,
      nowDeps,
    );

    const stored = db.store[`invites/${result.inviteId}`];
    assert.strictEqual(stored.tokenHash, hashToken(result.token));
    assert.ok(!JSON.stringify(stored).includes(result.token));
  });

  it("非メンバーは発行できない", async function() {
    const db = seeded();
    await assertHttpsError("permission-denied", () =>
      createInvite(
        db,
        {uid: "stranger", calendarId: "shared"},
        serverTimestamp,
        nowDeps,
      ),
    );
  });

  it("サインインしていなければ発行できない", async function() {
    const db = seeded();
    await assertHttpsError("unauthenticated", () =>
      createInvite(db, {uid: null, calendarId: "shared"}, serverTimestamp),
    );
  });

  it("存在しないカレンダーは発行できない", async function() {
    const db = seeded();
    await assertHttpsError("not-found", () =>
      createInvite(
        db,
        {uid: "member", calendarId: "missing"},
        serverTimestamp,
        nowDeps,
      ),
    );
  });
});

describe("previewInvite（Issue #90）", function() {
  it("カレンダー名と招待者名を返す", async function() {
    const db = seeded();
    const preview = await previewInvite(
      db,
      {uid: "stranger", token: "secret-token"},
      nowDeps,
    );

    assert.deepStrictEqual(preview, {
      calendarId: "shared",
      calendarName: "わが家",
      invitedByName: "母",
      alreadyMember: false,
    });
  });

  it("既にメンバーなら alreadyMember を返す", async function() {
    const db = seeded();
    const preview = await previewInvite(
      db,
      {uid: "owner", token: "secret-token"},
      nowDeps,
    );

    assert.strictEqual(preview.alreadyMember, true);
  });

  it("無効なトークンは not-found", async function() {
    const db = seeded();
    await assertHttpsError(
      "not-found",
      () => previewInvite(db, {uid: "stranger", token: "wrong"}, nowDeps),
      "not-found",
    );
  });

  it("期限切れは理由 expired を返す", async function() {
    const db = seeded({expiresAt: new Date(now.getTime() - 1)});
    await assertHttpsError(
      "failed-precondition",
      () => previewInvite(db, {uid: "stranger", token: "secret-token"}, nowDeps),
      "expired",
    );
  });

  it("取り消し済みは理由 revoked を返す", async function() {
    const db = seeded({revoked: true});
    await assertHttpsError(
      "failed-precondition",
      () => previewInvite(db, {uid: "stranger", token: "secret-token"}, nowDeps),
      "revoked",
    );
  });

  it("使用回数超過は理由 used を返す", async function() {
    const db = seeded({usedCount: 1});
    await assertHttpsError(
      "failed-precondition",
      () => previewInvite(db, {uid: "stranger", token: "secret-token"}, nowDeps),
      "used",
    );
  });
});

describe("acceptInvite（Issue #90）", function() {
  it("受諾するとメンバーに追加され、使用回数が増える", async function() {
    const db = seeded();
    const result = await acceptInvite(
      db,
      {uid: "stranger", token: "secret-token"},
      serverTimestamp,
      nowDeps,
    );

    assert.deepStrictEqual(result, {
      calendarId: "shared",
      alreadyMember: false,
    });
    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, [
      "owner",
      "member",
      "stranger",
    ]);
    assert.strictEqual(db.store["invites/invite-1"].usedCount, 1);
  });

  it("既にメンバーなら成功扱いで使用回数を増やさない（冪等）", async function() {
    const db = seeded();
    const result = await acceptInvite(
      db,
      {uid: "member", token: "secret-token"},
      serverTimestamp,
      nowDeps,
    );

    assert.strictEqual(result.alreadyMember, true);
    assert.strictEqual(db.store["invites/invite-1"].usedCount, 0);
    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, [
      "owner",
      "member",
    ]);
  });

  it("個人カレンダーの招待も受諾できる", async function() {
    const db = fakeDb({
      "calendars/personal": {
        name: "父のカレンダー",
        memberIds: ["owner"],
        creatorId: "owner",
        ownerId: "owner",
      },
      "invites/invite-1": invite({calendarId: "personal", invitedBy: "owner"}),
    });

    const result = await acceptInvite(
      db,
      {uid: "stranger", token: "secret-token"},
      serverTimestamp,
      nowDeps,
    );

    assert.strictEqual(result.calendarId, "personal");
    assert.deepStrictEqual(db.store["calendars/personal"].memberIds, [
      "owner",
      "stranger",
    ]);
  });

  it("期限切れのリンクでは参加できない", async function() {
    const db = seeded({expiresAt: new Date(now.getTime() - 1)});
    await assertHttpsError(
      "failed-precondition",
      () =>
        acceptInvite(
          db,
          {uid: "stranger", token: "secret-token"},
          serverTimestamp,
          nowDeps,
        ),
      "expired",
    );
    assert.deepStrictEqual(db.store["calendars/shared"].memberIds, [
      "owner",
      "member",
    ]);
  });

  it("取り消し済みのリンクでは参加できない", async function() {
    const db = seeded({revoked: true});
    await assertHttpsError(
      "failed-precondition",
      () =>
        acceptInvite(
          db,
          {uid: "stranger", token: "secret-token"},
          serverTimestamp,
          nowDeps,
        ),
      "revoked",
    );
  });

  it("使用回数を超えたリンクでは参加できない", async function() {
    const db = seeded({usedCount: 1});
    await assertHttpsError(
      "failed-precondition",
      () =>
        acceptInvite(
          db,
          {uid: "stranger", token: "secret-token"},
          serverTimestamp,
          nowDeps,
        ),
      "used",
    );
  });

  it("サインインしていなければ受諾できない", async function() {
    const db = seeded();
    await assertHttpsError("unauthenticated", () =>
      acceptInvite(db, {uid: null, token: "secret-token"}, serverTimestamp),
    );
  });
});

describe("revokeInvite（Issue #90）", function() {
  it("発行者本人は取り消せる", async function() {
    const db = seeded();
    await revokeInvite(db, {uid: "member", inviteId: "invite-1"}, serverTimestamp);

    assert.strictEqual(db.store["invites/invite-1"].revoked, true);
  });

  it("オーナーは他人が発行したリンクを取り消せる", async function() {
    const db = seeded();
    await revokeInvite(db, {uid: "owner", inviteId: "invite-1"}, serverTimestamp);

    assert.strictEqual(db.store["invites/invite-1"].revoked, true);
  });

  it("発行者でもオーナーでもないメンバーは取り消せない", async function() {
    const db = seeded({invitedBy: "owner"}, {memberIds: ["owner", "member"]});
    await assertHttpsError("permission-denied", () =>
      revokeInvite(db, {uid: "member", inviteId: "invite-1"}, serverTimestamp),
    );
    assert.strictEqual(db.store["invites/invite-1"].revoked, false);
  });

  it("存在しない招待は not-found", async function() {
    const db = seeded();
    await assertHttpsError("not-found", () =>
      revokeInvite(db, {uid: "owner", inviteId: "missing"}, serverTimestamp),
    );
  });
});

describe("listInvites（Issue #90）", function() {
  it("メンバーは一覧を取得でき、トークンのハッシュは含まれない", async function() {
    const db = seeded();
    const {invites} = await listInvites(
      db,
      {uid: "member", calendarId: "shared"},
      nowDeps,
    );

    assert.strictEqual(invites.length, 1);
    assert.deepStrictEqual(invites[0], {
      id: "invite-1",
      invitedBy: "member",
      expiresAt: new Date(now.getTime() + 60 * 60 * 1000).toISOString(),
      maxUses: 1,
      usedCount: 0,
      revoked: false,
      active: true,
    });
  });

  it("期限切れは active=false になる", async function() {
    const db = seeded({expiresAt: new Date(now.getTime() - 1)});
    const {invites} = await listInvites(
      db,
      {uid: "member", calendarId: "shared"},
      nowDeps,
    );

    assert.strictEqual(invites[0].active, false);
  });

  it("非メンバーは一覧を取得できない", async function() {
    const db = seeded();
    await assertHttpsError("permission-denied", () =>
      listInvites(db, {uid: "stranger", calendarId: "shared"}, nowDeps),
    );
  });
});

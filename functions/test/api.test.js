"use strict";

const assert = require("node:assert");
const {createApiHandler} = require("../api");
const {createRateLimiter} = require("../api/ratelimit");

// Firestore（Admin SDK）の最小フェイク。パス → データの Map を保持し、
// ドキュメント取得と where / orderBy / startAfter / limit の組み合わせを模す。
function fakeDb(seed) {
  const store = {...seed};

  const snapshotOf = (path) => ({
    exists: store[path] !== undefined,
    id: path.split("/").pop(),
    data: () => store[path],
  });

  const valueOf = (value) => (value instanceof Date ? value.getTime() : value);

  const matches = (data, {field, op, value}) => {
    const actual = valueOf(data[field]);
    const expected = valueOf(value);
    if (op === "==") return actual === expected;
    if (op === ">=") return actual >= expected;
    if (op === "<") return actual < expected;
    if (op === "array-contains") {
      return Array.isArray(data[field]) && data[field].includes(value);
    }
    throw new Error(`unsupported op: ${op}`);
  };

  function queryOf(name, state) {
    const next = (patch) => queryOf(name, {...state, ...patch});
    return {
      where(field, op, value) {
        return next({filters: [...state.filters, {field, op, value}]});
      },
      orderBy(field) {
        return next({order: field});
      },
      startAfter(doc) {
        return next({after: doc.id});
      },
      limit(count) {
        return next({max: count});
      },
      async get() {
        let docs = Object.keys(store)
          .filter((path) => path.startsWith(`${name}/`))
          .filter((path) =>
            state.filters.every((filter) => matches(store[path], filter)),
          )
          .map(snapshotOf);
        if (state.order) {
          docs.sort((a, b) => {
            const left = valueOf(a.data()[state.order]);
            const right = valueOf(b.data()[state.order]);
            if (left < right) return -1;
            if (left > right) return 1;
            return a.id < b.id ? -1 : 1;
          });
        }
        if (state.after) {
          const index = docs.findIndex((doc) => doc.id === state.after);
          docs = index === -1 ? [] : docs.slice(index + 1);
        }
        if (state.max !== null) docs = docs.slice(0, state.max);
        return {docs, empty: docs.length === 0};
      },
    };
  }

  return {
    store,
    doc(path) {
      return {path, async get() {
        return snapshotOf(path);
      }};
    },
    collection(name) {
      return queryOf(name, {filters: [], order: null, after: null, max: null});
    },
  };
}

// verifyIdToken のフェイク。`token-<uid>` 形式だけを有効なトークンとみなす。
const fakeAuth = {
  async verifyIdToken(token) {
    const match = /^token-(.+)$/.exec(token);
    if (!match) throw new Error("invalid token");
    return {uid: match[1]};
  },
};

// express 風のレスポンスを記録するフェイク。
function fakeRes() {
  return {
    statusCode: null,
    body: null,
    headers: {},
    set(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  };
}

function seed() {
  const at = (iso) => new Date(iso);
  const event = (id, overrides) => ({
    [`events/${id}`]: {
      title: `予定${id}`,
      creatorId: "papa",
      participantIds: ["papa"],
      calendarId: "family",
      startAt: at("2026-07-14T09:00:00Z"),
      endAt: at("2026-07-14T10:00:00Z"),
      allDay: false,
      type: "confirmed",
      memo: "",
      reminderOffsets: {papa: [60]},
      updatedBy: "papa",
      createdAt: at("2026-07-01T00:00:00Z"),
      updatedAt: at("2026-07-01T00:00:00Z"),
      deleted: false,
      ...overrides,
    },
  });

  return fakeDb({
    "users/papa": {name: "パパ", email: "papa@example.com", color: "#FF0000"},
    "calendars/family": {
      name: "わが家",
      memberIds: ["papa", "mama"],
      creatorId: "papa",
      ownerId: "papa",
    },
    "calendars/personal": {
      name: "あかちゃん",
      memberIds: ["papa"],
      creatorId: "papa",
      ownerId: "papa",
    },
    "calendars/others": {
      name: "よそのおうち",
      memberIds: ["stranger"],
      creatorId: "stranger",
      ownerId: "stranger",
    },
    ...event("e1", {startAt: at("2026-07-14T09:00:00Z")}),
    ...event("e2", {startAt: at("2026-07-15T09:00:00Z")}),
    ...event("e3", {startAt: at("2026-07-16T09:00:00Z")}),
    // 期間外（7月）。
    ...event("e-out", {startAt: at("2026-08-01T09:00:00Z")}),
    // ソフト削除済み（返してはならない）。
    ...event("e-deleted", {
      startAt: at("2026-07-17T09:00:00Z"),
      deleted: true,
    }),
    // 他人のカレンダーの予定。
    ...event("e-others", {
      calendarId: "others",
      creatorId: "stranger",
      startAt: at("2026-07-14T09:00:00Z"),
    }),
  });
}

// ハンドラを 1 回呼び、ステータスとボディを返す。
async function call(db, {path, query = {}, token = "token-papa", method = "GET",
  handler = null} = {}) {
  const apiHandler = handler || createApiHandler({db, auth: fakeAuth});
  const res = fakeRes();
  const headers = {};
  if (token !== null) headers.authorization = `Bearer ${token}`;
  await apiHandler({method, path, query, headers}, res);
  return {status: res.statusCode, body: res.body, headers: res.headers};
}

describe("外部向け読み取り専用 REST API（Issue #103）", function() {
  describe("認証", function() {
    it("Authorization ヘッダが無いと 401", async function() {
      const res = await call(seed(), {path: "/v1/calendars", token: null});

      assert.strictEqual(res.status, 401);
      assert.strictEqual(res.body.error.code, "unauthenticated");
    });

    it("不正・期限切れのトークンは 401", async function() {
      const res = await call(seed(), {path: "/v1/calendars", token: "bogus"});

      assert.strictEqual(res.status, 401);
      assert.strictEqual(res.body.error.code, "unauthenticated");
    });

    it("読み取り専用のため GET 以外は 400", async function() {
      const res = await call(seed(), {path: "/v1/events", method: "POST"});

      assert.strictEqual(res.status, 400);
      assert.strictEqual(res.body.error.code, "invalid_argument");
    });
  });

  describe("GET /v1/me", function() {
    it("自分のプロフィールを返す", async function() {
      const res = await call(seed(), {path: "/v1/me"});

      assert.strictEqual(res.status, 200);
      assert.deepStrictEqual(res.body, {
        uid: "papa",
        name: "パパ",
        color: "#FF0000",
      });
    });
  });

  describe("GET /v1/calendars", function() {
    it("自分が参加しているカレンダーだけを名前昇順で返す", async function() {
      const res = await call(seed(), {path: "/v1/calendars"});

      assert.strictEqual(res.status, 200);
      assert.deepStrictEqual(
        res.body.calendars.map((calendar) => calendar.id),
        ["personal", "family"],
      );
      assert.deepStrictEqual(res.body.calendars[1], {
        id: "family",
        name: "わが家",
        ownerId: "papa",
        memberIds: ["papa", "mama"],
      });
    });

    it("メンバーでないカレンダーは 404（存在も漏らさない）", async function() {
      const res = await call(seed(), {path: "/v1/calendars/others"});

      assert.strictEqual(res.status, 404);
      assert.strictEqual(res.body.error.code, "not_found");
    });

    it("存在しないカレンダーも同じ 404", async function() {
      const res = await call(seed(), {path: "/v1/calendars/missing"});

      assert.strictEqual(res.status, 404);
      assert.strictEqual(res.body.error.code, "not_found");
    });
  });

  describe("GET /v1/events", function() {
    const july = {
      calendarId: "family",
      from: "2026-07-01T00:00:00Z",
      to: "2026-08-01T00:00:00Z",
    };

    it("期間内の予定を返し、削除済み・期間外を含まない", async function() {
      const res = await call(seed(), {path: "/v1/events", query: july});

      assert.strictEqual(res.status, 200);
      assert.deepStrictEqual(
        res.body.events.map((event) => event.id),
        ["e1", "e2", "e3"],
      );
      assert.strictEqual(res.body.nextCursor, null);
    });

    it("時刻は ISO 8601（UTC）で、deleted / updatedBy は返さない",
      async function() {
        const res = await call(seed(), {path: "/v1/events", query: july});

        const event = res.body.events[0];
        assert.strictEqual(event.startAt, "2026-07-14T09:00:00Z");
        assert.strictEqual(event.endAt, "2026-07-14T10:00:00Z");
        assert.strictEqual(event.createdAt, "2026-07-01T00:00:00Z");
        assert.strictEqual(event.updatedAt, "2026-07-01T00:00:00Z");
        assert.ok(!("deleted" in event));
        assert.ok(!("updatedBy" in event));
        assert.deepStrictEqual(event.reminderOffsets, {papa: [60]});
      });

    it("メンバーでないカレンダーを指定すると 404", async function() {
      const res = await call(seed(), {
        path: "/v1/events",
        query: {...july, calendarId: "others"},
      });

      assert.strictEqual(res.status, 404);
      assert.strictEqual(res.body.error.code, "not_found");
    });

    it("calendarId / from / to が無いと 400", async function() {
      const res = await call(seed(), {path: "/v1/events", query: {}});

      assert.strictEqual(res.status, 400);
      assert.strictEqual(res.body.error.code, "invalid_argument");
    });

    it("from が ISO 8601 でないと 400", async function() {
      const res = await call(seed(), {
        path: "/v1/events",
        query: {...july, from: "きのう"},
      });

      assert.strictEqual(res.status, 400);
    });

    it("limit が範囲外だと 400", async function() {
      const res = await call(seed(), {
        path: "/v1/events",
        query: {...july, limit: "501"},
      });

      assert.strictEqual(res.status, 400);
    });

    it("limit / cursor で全件を重複なく取得できる", async function() {
      const db = seed();
      const collected = [];
      let cursor = null;

      do {
        const query = {...july, limit: "2"};
        if (cursor) query.cursor = cursor;
        const res = await call(db, {path: "/v1/events", query});
        assert.strictEqual(res.status, 200);
        collected.push(...res.body.events.map((event) => event.id));
        cursor = res.body.nextCursor;
      } while (cursor);

      assert.deepStrictEqual(collected, ["e1", "e2", "e3"]);
      assert.strictEqual(new Set(collected).size, collected.length);
    });

    it("他カレンダーの予定を指すカーソルは 400", async function() {
      const cursor = Buffer.from("e-others", "utf8").toString("base64url");

      const res = await call(seed(), {
        path: "/v1/events",
        query: {...july, cursor},
      });

      assert.strictEqual(res.status, 400);
      assert.strictEqual(res.body.error.code, "invalid_argument");
    });
  });

  describe("GET /v1/events/{eventId}", function() {
    it("メンバーなら 1 件返す", async function() {
      const res = await call(seed(), {path: "/v1/events/e1"});

      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.body.id, "e1");
      assert.strictEqual(res.body.calendarId, "family");
    });

    it("他人のカレンダーの予定は 404", async function() {
      const res = await call(seed(), {path: "/v1/events/e-others"});

      assert.strictEqual(res.status, 404);
    });

    it("削除済みの予定は 404", async function() {
      const res = await call(seed(), {path: "/v1/events/e-deleted"});

      assert.strictEqual(res.status, 404);
    });
  });

  describe("CORS", function() {
    it("許可オリジンには CORS ヘッダを返す", async function() {
      const handler = createApiHandler({
        db: seed(),
        auth: fakeAuth,
        env: {API_ALLOWED_ORIGINS: "https://kansuke.example"},
      });
      const res = fakeRes();

      await handler(
        {
          method: "OPTIONS",
          path: "/v1/me",
          query: {},
          headers: {origin: "https://kansuke.example"},
        },
        res,
      );

      assert.strictEqual(res.statusCode, 204);
      assert.strictEqual(
        res.headers["Access-Control-Allow-Origin"],
        "https://kansuke.example",
      );
    });

    it("許可外オリジンには CORS ヘッダを付けない", async function() {
      const handler = createApiHandler({
        db: seed(),
        auth: fakeAuth,
        env: {API_ALLOWED_ORIGINS: "https://kansuke.example"},
      });
      const res = fakeRes();

      await handler(
        {
          method: "OPTIONS",
          path: "/v1/me",
          query: {},
          headers: {origin: "https://evil.example"},
        },
        res,
      );

      assert.strictEqual(
        res.headers["Access-Control-Allow-Origin"],
        undefined,
      );
    });
  });

  describe("レートリミット", function() {
    it("上限を超えると 429", async function() {
      const db = seed();
      const handler = createApiHandler({
        db,
        auth: fakeAuth,
        now: () => new Date("2026-07-14T00:00:00Z"),
        rateLimiter: createRateLimiter({limit: 2, windowMs: 60000}),
      });

      const first = await call(db, {path: "/v1/me", handler});
      const second = await call(db, {path: "/v1/me", handler});
      const third = await call(db, {path: "/v1/me", handler});

      assert.strictEqual(first.status, 200);
      assert.strictEqual(second.status, 200);
      assert.strictEqual(third.status, 429);
      assert.strictEqual(third.body.error.code, "resource_exhausted");
    });
  });

  it("未知のパスは 404", async function() {
    const res = await call(seed(), {path: "/v2/events"});

    assert.strictEqual(res.status, 404);
  });
});

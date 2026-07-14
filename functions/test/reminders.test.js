"use strict";

const assert = require("node:assert");
const {
  buildReminders,
  formatLeadTime,
  needsRebuild,
  sendDueReminders,
  syncEventReminders,
} = require("../reminders");

const now = new Date("2026-07-14T09:00:00Z");
const deps = (() => {
  let seq = 0;
  return {now: () => now, newId: () => `r${++seq}`};
})();

// Firestore（Admin SDK）の最小フェイク。パス → データの Map を保持し、
// reminders.js が使う操作だけ（doc の get/update/delete、`==` / `<=` の where、
// limit、batch、サブコレクションの取得）を模す。
function fakeDb(seed = {}) {
  const store = {...seed};

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
      async update(patch) {
        store[path] = {...store[path], ...patch};
      },
      async delete() {
        delete store[path];
      },
    };
  }

  const matches = (data, [field, op, value]) => {
    if (op === "==") return data[field] === value;
    if (op === "<=") return data[field].getTime() <= value.getTime();
    throw new Error(`unsupported op: ${op}`);
  };

  function queryOf(name, conditions, max) {
    return {
      where(field, op, value) {
        return queryOf(name, [...conditions, [field, op, value]], max);
      },
      limit(count) {
        return queryOf(name, conditions, count);
      },
      async get() {
        const docs = Object.keys(store)
          .filter((path) => path.startsWith(`${name}/`))
          .filter((path) => path.slice(name.length + 1).indexOf("/") === -1)
          .filter((path) =>
            conditions.every((condition) => matches(store[path], condition)),
          )
          .slice(0, max === undefined ? Infinity : max)
          .map(snapshotOf);
        return {empty: docs.length === 0, docs, size: docs.length};
      },
    };
  }

  return {
    store,
    doc: docRef,
    collection(name) {
      return queryOf(name, [], undefined);
    },
    batch() {
      const ops = [];
      return {
        set(ref, data) {
          ops.push(() => {
            store[ref.path] = data;
          });
        },
        delete(ref) {
          ops.push(() => {
            delete store[ref.path];
          });
        },
        async commit() {
          ops.forEach((op) => op());
        },
      };
    },
  };
}

// FCM の最小フェイク。送信を記録し、指定トークンには失敗（無効トークン）を返す。
function fakeMessaging(invalidTokens = []) {
  const calls = [];
  return {
    calls,
    async sendEachForMulticast(message) {
      calls.push(message);
      const responses = message.tokens.map((token) =>
        invalidTokens.includes(token) ?
          {
            success: false,
            error: {code: "messaging/registration-token-not-registered"},
          } :
          {success: true},
      );
      return {
        responses,
        successCount: responses.filter((r) => r.success).length,
        failureCount: responses.filter((r) => !r.success).length,
      };
    },
  };
}

const event = (overrides = {}) => ({
  title: "歯医者",
  startAt: new Date("2026-07-14T12:00:00Z"),
  participantIds: ["papa", "mama"],
  reminderOffsets: {papa: [60]},
  deleted: false,
  ...overrides,
});

describe("buildReminders（Issue #14 / FR-5）", function() {
  it("設定した本人ごとに triggerAt = startAt - offset で生成する", function() {
    const built = buildReminders(
      "e1",
      event({reminderOffsets: {papa: [60], mama: [120]}}),
      {
        now: () => now,
        newId: (() => {
          let seq = 0;
          return () => `r${++seq}`;
        })(),
      },
    );

    assert.deepStrictEqual(
      built.map((r) => [r.data.ownerId, r.data.triggerAt.toISOString()]),
      [
        // uid 昇順（mama → papa）。それぞれ自分の offset だけを持つ。
        ["mama", "2026-07-14T10:00:00.000Z"],
        ["papa", "2026-07-14T11:00:00.000Z"],
      ],
    );
    for (const reminder of built) {
      assert.strictEqual(reminder.data.eventId, "e1");
      assert.strictEqual(reminder.data.sent, false);
    }
  });

  it("設定していない参加者には生成しない", function() {
    const built = buildReminders(
      "e1",
      event({participantIds: ["papa", "mama"], reminderOffsets: {papa: [60]}}),
      deps,
    );

    assert.deepStrictEqual(
      built.map((r) => r.data.ownerId),
      ["papa"],
    );
  });

  it("削除済み・開始時刻なし・設定なしは生成しない", function() {
    assert.deepStrictEqual(
      buildReminders("e1", event({deleted: true}), deps),
      [],
    );
    assert.deepStrictEqual(buildReminders("e1", null, deps), []);
    assert.deepStrictEqual(
      buildReminders("e1", event({startAt: null}), deps),
      [],
    );
    assert.deepStrictEqual(
      buildReminders("e1", event({reminderOffsets: {}}), deps),
      [],
    );
    assert.deepStrictEqual(
      buildReminders("e1", event({reminderOffsets: {papa: []}}), deps),
      [],
    );
  });

  it("旧形式（予定で共有する number[]）は無視する", function() {
    assert.deepStrictEqual(
      buildReminders("e1", event({reminderOffsets: [60]}), deps),
      [],
    );
  });

  it("配信時刻が既に過ぎている offset は生成しない", function() {
    // 開始まで 3 時間。1440分（前日）前は過去なので作らない。
    const built = buildReminders(
      "e1",
      event({reminderOffsets: {papa: [1440]}}),
      deps,
    );
    assert.deepStrictEqual(built, []);
  });

  it("offset の重複・不正値を除いて昇順に扱う", function() {
    const built = buildReminders(
      "e1",
      event({
        startAt: new Date("2026-07-15T12:00:00Z"),
        reminderOffsets: {papa: [60, 60, -5, 1.5, 30]},
      }),
      deps,
    );

    // offset 昇順（30分前 → 60分前）＝ triggerAt は降順になる。
    assert.deepStrictEqual(
      built.map((r) => r.data.triggerAt.toISOString()),
      ["2026-07-15T11:30:00.000Z", "2026-07-15T11:00:00.000Z"],
    );
  });
});

describe("needsRebuild（多重送信防止）", function() {
  it("作成・削除は再生成する", function() {
    assert.strictEqual(needsRebuild(null, event()), true);
    assert.strictEqual(needsRebuild(event(), null), true);
  });

  it("startAt / reminderOffsets / deleted の変更で再生成する", function() {
    const before = event();
    assert.strictEqual(
      needsRebuild(before, event({startAt: new Date("2026-07-14T13:00:00Z")})),
      true,
    );
    assert.strictEqual(
      needsRebuild(before, event({reminderOffsets: {papa: [30]}})),
      true,
    );
    assert.strictEqual(
      needsRebuild(before, event({reminderOffsets: {papa: [60], mama: [10]}})),
      true,
    );
    assert.strictEqual(needsRebuild(before, event({deleted: true})), true);
  });

  it("タイトルなど無関係な更新では再生成しない（送信済みが作り直されるのを防ぐ）",
      function() {
        assert.strictEqual(
          needsRebuild(event(), event({title: "歯医者（変更）"})),
          false,
        );
        assert.strictEqual(
          needsRebuild(event(), event({participantIds: ["papa"]})),
          false,
        );
      });
});

describe("syncEventReminders（onEventWrite）", function() {
  it("旧 reminders を破棄して再生成する", async function() {
    const db = fakeDb({
      "reminders/old": {
        eventId: "e1",
        ownerId: "papa",
        triggerAt: new Date("2026-07-14T10:00:00Z"),
        sent: false,
      },
      "reminders/other": {
        eventId: "e2",
        ownerId: "papa",
        triggerAt: new Date("2026-07-14T10:00:00Z"),
        sent: false,
      },
    });

    const result = await syncEventReminders(
      db,
      {
        eventId: "e1",
        before: event({reminderOffsets: {papa: [120]}}),
        after: event({reminderOffsets: {papa: [60]}}),
      },
      {now: () => now, newId: () => "new1"},
    );

    assert.deepStrictEqual(result, {deleted: 1, created: 1});
    assert.strictEqual(db.store["reminders/old"], undefined);
    assert.ok(db.store["reminders/other"], "他の予定の reminder は消さない");
    assert.deepStrictEqual(db.store["reminders/new1"], {
      eventId: "e1",
      ownerId: "papa",
      triggerAt: new Date("2026-07-14T11:00:00Z"),
      sent: false,
    });
  });

  it("ソフト削除では reminders を消すだけ", async function() {
    const db = fakeDb({
      "reminders/old": {
        eventId: "e1",
        ownerId: "papa",
        triggerAt: new Date("2026-07-14T11:00:00Z"),
        sent: false,
      },
    });

    const result = await syncEventReminders(
      db,
      {eventId: "e1", before: event(), after: event({deleted: true})},
      deps,
    );

    assert.deepStrictEqual(result, {deleted: 1, created: 0});
    assert.strictEqual(db.store["reminders/old"], undefined);
  });

  it("無関係な更新では Firestore に触らない", async function() {
    const db = fakeDb({
      "reminders/keep": {
        eventId: "e1",
        ownerId: "papa",
        triggerAt: new Date("2026-07-14T11:00:00Z"),
        sent: true,
      },
    });

    const result = await syncEventReminders(
      db,
      {eventId: "e1", before: event(), after: event({memo: "保険証"})},
      deps,
    );

    assert.deepStrictEqual(result, {deleted: 0, created: 0});
    assert.strictEqual(db.store["reminders/keep"].sent, true);
  });
});

describe("sendDueReminders（毎分スケジュール）", function() {
  const seed = () => ({
    "events/e1": event({participantIds: ["papa"]}),
    // startAt（12:00）の 3 時間前。now（09:00）時点で配信時刻が到来している。
    "reminders/due": {
      eventId: "e1",
      ownerId: "papa",
      triggerAt: new Date("2026-07-14T09:00:00Z"),
      sent: false,
    },
    "reminders/future": {
      eventId: "e1",
      ownerId: "papa",
      triggerAt: new Date("2026-07-14T11:00:00Z"),
      sent: false,
    },
    "reminders/alreadySent": {
      eventId: "e1",
      ownerId: "papa",
      triggerAt: new Date("2026-07-14T08:00:00Z"),
      sent: true,
    },
    "users/papa/devices/tokenA": {updatedAt: "SERVER_TS"},
    "users/papa/devices/tokenB": {updatedAt: "SERVER_TS"},
  });

  it("due な分だけ所有者の全デバイスへ送信し sent=true にする", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();

    const result = await sendDueReminders(db, messaging, {now: () => now});

    assert.deepStrictEqual(result, {processed: 1, sent: 2, prunedTokens: 0});
    assert.strictEqual(messaging.calls.length, 1);
    assert.deepStrictEqual(messaging.calls[0].tokens, ["tokenA", "tokenB"]);
    assert.strictEqual(messaging.calls[0].notification.title, "歯医者");
    assert.strictEqual(
      messaging.calls[0].notification.body,
      "3時間後に開始します",
    );
    assert.deepStrictEqual(messaging.calls[0].data, {eventId: "e1"});

    assert.strictEqual(db.store["reminders/due"].sent, true);
    assert.strictEqual(db.store["reminders/future"].sent, false);
  });

  it("送信済み・未到来は対象外（多重送信しない）", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();

    await sendDueReminders(db, messaging, {now: () => now});
    const secondRun = await sendDueReminders(db, messaging, {now: () => now});

    assert.strictEqual(secondRun.processed, 0);
    assert.strictEqual(messaging.calls.length, 1, "2 回目は送信しない");
  });

  it("無効トークンの devices を削除する", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging(["tokenB"]);

    const result = await sendDueReminders(db, messaging, {now: () => now});

    assert.deepStrictEqual(result, {processed: 1, sent: 1, prunedTokens: 1});
    assert.ok(db.store["users/papa/devices/tokenA"], "有効トークンは残す");
    assert.strictEqual(db.store["users/papa/devices/tokenB"], undefined);
    assert.strictEqual(db.store["reminders/due"].sent, true);
  });

  it("削除済み・消えた予定は送信せず sent=true にする", async function() {
    const db = fakeDb({...seed(), "events/e1": event({deleted: true})});
    const messaging = fakeMessaging();

    const result = await sendDueReminders(db, messaging, {now: () => now});

    assert.deepStrictEqual(result, {processed: 1, sent: 0, prunedTokens: 0});
    assert.strictEqual(messaging.calls.length, 0);
    assert.strictEqual(db.store["reminders/due"].sent, true);
  });

  it("トークン未登録のユーザーには送信しない", async function() {
    const store = seed();
    delete store["users/papa/devices/tokenA"];
    delete store["users/papa/devices/tokenB"];
    const db = fakeDb(store);
    const messaging = fakeMessaging();

    const result = await sendDueReminders(db, messaging, {now: () => now});

    assert.strictEqual(messaging.calls.length, 0);
    assert.strictEqual(result.processed, 1);
    assert.strictEqual(db.store["reminders/due"].sent, true);
  });
});

describe("formatLeadTime", function() {
  it("分・時間・日で表現する", function() {
    assert.strictEqual(formatLeadTime(10), "10分後に開始します");
    assert.strictEqual(formatLeadTime(60), "1時間後に開始します");
    assert.strictEqual(formatLeadTime(90), "90分後に開始します");
    assert.strictEqual(formatLeadTime(1440), "1日後に開始します");
    assert.strictEqual(formatLeadTime(0), "まもなく開始します");
  });
});

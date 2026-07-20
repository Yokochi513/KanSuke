"use strict";

const assert = require("node:assert");
const {
  buildMessage,
  classifyChange,
  formatEventDate,
  hasMeaningfulChange,
  notifyEventChange,
  shouldThrottle,
} = require("../notifications");

const now = new Date("2026-07-14T09:00:00Z");

// Firestore（Admin SDK）の最小フェイク。パス → データの Map を保持し、
// notifications.js が使う操作だけ（doc の get/set/delete、サブコレクションの
// 取得）を模す。reminders のテストと同じ方針。
function fakeDb(seed = {}) {
  const store = {...seed};

  const snapshotOf = (path) => ({
    exists: store[path] !== undefined,
    id: path.split("/").pop(),
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
      async delete() {
        delete store[path];
      },
    };
  }

  return {
    store,
    doc: docRef,
    collection(name) {
      return {
        async get() {
          const docs = Object.keys(store)
            .filter((path) => path.startsWith(`${name}/`))
            .filter((path) => path.slice(name.length + 1).indexOf("/") === -1)
            .map(snapshotOf);
          return {empty: docs.length === 0, docs, size: docs.length};
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
  endAt: new Date("2026-07-14T13:00:00Z"),
  allDay: false,
  type: "confirmed",
  memo: "",
  participantIds: ["papa", "mama"],
  reminderOffsets: {papa: [60]},
  updatedBy: "papa",
  deleted: false,
  calendarId: "cal1",
  ...overrides,
});

// 参加者・操作者名を含む標準的なシード。
const seed = () => ({
  "calendars/cal1": {memberIds: ["papa", "mama", "kids"]},
  "users/papa": {name: "パパ"},
  "users/mama": {name: "ママ"},
  "users/mama/devices/tokenM": {updatedAt: "SERVER_TS"},
  "users/kids/devices/tokenK1": {updatedAt: "SERVER_TS"},
  "users/kids/devices/tokenK2": {updatedAt: "SERVER_TS"},
});

describe("classifyChange（操作種別の判定 / Issue #77）", function() {
  it("作成・更新・削除を判定する", function() {
    assert.strictEqual(classifyChange(null, event()).action, "created");
    assert.strictEqual(
      classifyChange(event(), event({title: "内科"})).action,
      "updated",
    );
    assert.strictEqual(
      classifyChange(event(), event({deleted: true})).action,
      "deleted",
    );
  });

  it("物理削除（after なし）は通知しない", function() {
    assert.strictEqual(classifyChange(event(), null), null);
  });

  it("ソフト削除済みからの物理削除・両方削除済みは通知しない", function() {
    assert.strictEqual(
      classifyChange(event({deleted: true}), event({deleted: true})),
      null,
    );
  });

  it("共有項目が変わらない更新（個人設定・監査のみ）は通知しない", function() {
    assert.strictEqual(
      classifyChange(event(), event({reminderOffsets: {mama: [30]}})),
      null,
    );
    assert.strictEqual(
      classifyChange(event(), event({updatedBy: "mama"})),
      null,
    );
  });

  it("操作者は after.updatedBy から取る", function() {
    assert.strictEqual(
      classifyChange(event(), event({title: "内科", updatedBy: "mama"}))
        .operatorId,
      "mama",
    );
  });
});

describe("hasMeaningfulChange（共有項目の変化）", function() {
  it("共有される項目の変更を検出する", function() {
    assert.strictEqual(hasMeaningfulChange(event(), event({title: "内科"})),
      true);
    assert.strictEqual(
      hasMeaningfulChange(
        event(),
        event({startAt: new Date("2026-07-14T15:00:00Z")}),
      ),
      true,
    );
    assert.strictEqual(
      hasMeaningfulChange(event(), event({allDay: true})),
      true,
    );
    assert.strictEqual(
      hasMeaningfulChange(event(), event({type: "tentative"})),
      true,
    );
    assert.strictEqual(
      hasMeaningfulChange(event(), event({participantIds: ["papa"]})),
      true,
    );
    assert.strictEqual(
      hasMeaningfulChange(event(), event({calendarId: "cal2"})),
      true,
    );
  });

  it("個人設定・監査だけの変更は検出しない", function() {
    assert.strictEqual(
      hasMeaningfulChange(event(), event({reminderOffsets: {mama: [30]}})),
      false,
    );
    assert.strictEqual(
      hasMeaningfulChange(event(), event({updatedBy: "mama"})),
      false,
    );
  });

  it("参加者は順不同で比較する", function() {
    assert.strictEqual(
      hasMeaningfulChange(
        event({participantIds: ["papa", "mama"]}),
        event({participantIds: ["mama", "papa"]}),
      ),
      false,
    );
  });
});

describe("formatEventDate（日本時間・日本語）", function() {
  it("時刻ありは JST の日付＋時刻を返す", function() {
    // 2026-07-14T12:00:00Z = JST 21:00、火曜。
    assert.strictEqual(
      formatEventDate(new Date("2026-07-14T12:00:00Z"), false),
      "7月14日(火) 21:00",
    );
  });

  it("終日は時刻を出さない", function() {
    assert.strictEqual(
      formatEventDate(new Date("2026-07-14T00:00:00Z"), true),
      "7月14日(火)",
    );
  });

  it("UTC→JST の日付繰り上がりを扱う", function() {
    // 2026-07-14T15:00:00Z = JST 翌 15 日 00:00。
    assert.strictEqual(
      formatEventDate(new Date("2026-07-14T15:00:00Z"), false),
      "7月15日(水) 00:00",
    );
  });
});

describe("buildMessage（操作者・タイトル・日付・種別を含む）", function() {
  it("追加/変更/削除の文面を組み立てる", function() {
    assert.deepStrictEqual(buildMessage("created", event(), "パパ"), {
      title: "パパさんが予定を追加しました",
      body: "歯医者（7月14日(火) 21:00）",
    });
    assert.strictEqual(
      buildMessage("updated", event(), "パパ").title,
      "パパさんが予定を変更しました",
    );
    assert.strictEqual(
      buildMessage("deleted", event(), "パパ").title,
      "パパさんが予定を削除しました",
    );
  });
});

describe("shouldThrottle（過剰通知の抑制）", function() {
  it("直近送信から窓内の更新は抑制する", function() {
    const recent = new Date(now.getTime() - 60 * 1000);
    assert.strictEqual(shouldThrottle("updated", recent, now), true);
  });

  it("窓を超えた更新・初回は抑制しない", function() {
    const old = new Date(now.getTime() - 10 * 60 * 1000);
    assert.strictEqual(shouldThrottle("updated", old, now), false);
    assert.strictEqual(shouldThrottle("updated", null, now), false);
  });

  it("作成・削除は抑制しない", function() {
    const recent = new Date(now.getTime() - 60 * 1000);
    assert.strictEqual(shouldThrottle("created", recent, now), false);
    assert.strictEqual(shouldThrottle("deleted", recent, now), false);
  });
});

describe("notifyEventChange（配信先の選定と送信）", function() {
  it("操作者を除く参加者の全デバイスへ送り、状態を記録する", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();

    const result = await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: null, after: event()},
      {now: () => now},
    );

    assert.deepStrictEqual(result, {
      action: "created",
      notified: 3,
      recipients: 2,
      prunedTokens: 0,
      throttled: false,
    });
    // 操作者 papa には送らない。mama と kids のデバイスへ送る。
    assert.strictEqual(messaging.calls.length, 2);
    const tokens = messaging.calls.flatMap((call) => call.tokens);
    assert.deepStrictEqual(tokens.sort(), ["tokenK1", "tokenK2", "tokenM"]);
    assert.strictEqual(
      messaging.calls[0].notification.title,
      "パパさんが予定を追加しました",
    );
    assert.deepStrictEqual(messaging.calls[0].data, {
      type: "eventChange",
      action: "created",
      eventId: "e1",
      calendarId: "cal1",
    });
    assert.strictEqual(db.store["eventNotifications/e1"].lastAction, "created");
  });

  it("通知対象外（個人設定のみの更新）は送信しない", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();

    const result = await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: event(), after: event({reminderOffsets: {}})},
      {now: () => now},
    );

    assert.strictEqual(result.action, null);
    assert.strictEqual(messaging.calls.length, 0);
  });

  it("操作者以外に参加者がいなければ送信しない", async function() {
    const db = fakeDb({...seed(), "calendars/cal1": {memberIds: ["papa"]}});
    const messaging = fakeMessaging();

    const result = await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: null, after: event()},
      {now: () => now},
    );

    assert.strictEqual(result.recipients, 0);
    assert.strictEqual(messaging.calls.length, 0);
  });

  it("無効トークンの devices を削除する", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging(["tokenK1"]);

    const result = await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: null, after: event()},
      {now: () => now},
    );

    assert.strictEqual(result.prunedTokens, 1);
    assert.strictEqual(db.store["users/kids/devices/tokenK1"], undefined);
    assert.ok(db.store["users/kids/devices/tokenK2"], "有効トークンは残す");
  });

  it("操作者名が引けなければフォールバック表示にする", async function() {
    const store = seed();
    delete store["users/mama"];
    const db = fakeDb(store);
    const messaging = fakeMessaging();

    await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: event(), after: event({
        title: "内科",
        updatedBy: "mama",
      })},
      {now: () => now},
    );

    assert.strictEqual(
      messaging.calls[0].notification.title,
      "メンバーさんが予定を変更しました",
    );
  });

  it("連続する更新はスロットルし、窓を超えたら再び送る", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();
    const change = {
      eventId: "e1",
      before: event(),
      after: event({title: "内科"}),
    };

    const first = await notifyEventChange(db, messaging, change, {
      now: () => now,
    });
    assert.strictEqual(first.throttled, false);
    assert.strictEqual(first.action, "updated");

    // 1 分後の更新は抑制（送信しない）。
    const soon = new Date(now.getTime() + 60 * 1000);
    const second = await notifyEventChange(db, messaging, change, {
      now: () => soon,
    });
    assert.strictEqual(second.throttled, true);
    assert.strictEqual(second.notified, 0);
    assert.strictEqual(messaging.calls.length, 2, "1 回目のみ送信（mama/kids）");

    // 6 分後は窓を超えるので再び送る。
    const later = new Date(now.getTime() + 6 * 60 * 1000);
    const third = await notifyEventChange(db, messaging, change, {
      now: () => later,
    });
    assert.strictEqual(third.throttled, false);
    assert.strictEqual(messaging.calls.length, 4);
  });

  it("削除はスロットルせず送る", async function() {
    const db = fakeDb(seed());
    const messaging = fakeMessaging();
    // 直近に送信済みの状態を用意する。
    db.store["eventNotifications/e1"] = {
      lastNotifiedAt: now,
      lastAction: "created",
    };

    const soon = new Date(now.getTime() + 60 * 1000);
    const result = await notifyEventChange(
      db,
      messaging,
      {eventId: "e1", before: event(), after: event({deleted: true})},
      {now: () => soon},
    );

    assert.strictEqual(result.throttled, false);
    assert.strictEqual(result.action, "deleted");
    assert.ok(messaging.calls.length > 0);
  });
});

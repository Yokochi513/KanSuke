"use strict";

const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "demo-kansuke";
const rulesPath = path.resolve(__dirname, "../../firestore.rules");

// カレンダーの ID は UUID で統一されている（Issue #93）。テストでは読みやすさのため
// 固定文字列を使うが、'default' のような特別な ID はもう存在しない。
const familyCalendarId = "family-calendar";

// Issue #117: モデル（Event.fromMap）が必須とするフィールドをすべて備えた
// 正当な予定。テストはこれを基に、欠損・型不正などの差分だけを上書きして使う。
function validEvent(overrides = {}) {
  return {
    id: "event-1",
    title: "家族の予定",
    creatorId: "family-user",
    participantIds: ["family-user"],
    startAt: Timestamp.fromDate(new Date("2026-07-20T09:00:00Z")),
    endAt: Timestamp.fromDate(new Date("2026-07-20T10:00:00Z")),
    allDay: false,
    type: "confirmed",
    memo: "",
    reminderOffsets: {},
    updatedBy: "family-user",
    createdAt: Timestamp.fromDate(new Date("2026-07-15T00:00:00Z")),
    updatedAt: serverTimestamp(),
    deleted: false,
    calendarId: familyCalendarId,
    recurrenceFrequency: null,
    recurrenceCount: null,
    recurrenceExceptions: [],
    recurrenceUntil: null,
    ...overrides,
  };
}

let testEnvironment;

function dbFor(uid) {
  return testEnvironment.authenticatedContext(uid).firestore();
}

async function seedFamilyMembers() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/family-user"), {
      name: "Family",
    });
    await setDoc(doc(context.firestore(), "users/other-family-user"), {
      name: "Other Family",
    });
    // FR-8: 家族のカレンダー。予定は calendarId でこのカレンダーに紐づく。
    await setDoc(doc(context.firestore(), `calendars/${familyCalendarId}`), {
      name: "わが家",
      memberIds: ["family-user", "other-family-user"],
      creatorId: "family-user",
      ownerId: "family-user",
    });
  });
}

before(async function() {
  this.timeout(10000);
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(rulesPath, "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await seedFamilyMembers();
});

after(async () => {
  if (testEnvironment) {
    await testEnvironment.cleanup();
  }
});

describe("Firestore Security Rules (NFR-4)", () => {
  it("家族メンバーは users を個別に読めて自分の情報だけを書ける", async () => {
    const familyDb = dbFor("family-user");

    await assertSucceeds(getDoc(doc(familyDb, "users/other-family-user")));
    await assertSucceeds(setDoc(doc(familyDb, "users/family-user"), {
      name: "Updated",
    }));
    await assertFails(setDoc(doc(familyDb, "users/other-family-user"), {
      name: "Denied",
    }));
  });

  it("users は誰も列挙できない（Issue #89）", async () => {
    // サインアップは開放されている（Issue #87）ため、列挙を許すと第三者が
    // 全ユーザーの名前・メール・色を取得できてしまう。
    await assertFails(getDocs(collection(dbFor("family-user"), "users")));
    await assertFails(getDocs(collection(dbFor("outsider"), "users")));
  });

  it("家族メンバーは events を読み書きできる", async () => {
    const event = doc(dbFor("family-user"), "events/event-1");

    await assertSucceeds(setDoc(event, validEvent()));
    await assertSucceeds(getDoc(event));
    await assertSucceeds(deleteDoc(event));
  });

  it("必須フィールドを欠いた不正な予定は作成できない（Issue #117）", async () => {
    // 報告された不正データ（title / deleted だけ）。calendarId を付けて
    // 参加者チェックを通しても、startAt などの必須フィールドが無いため弾く。
    const familyDb = dbFor("family-user");

    await assertFails(setDoc(doc(familyDb, "events/malformed-1"), {
      title: "不正な予定",
      deleted: false,
      calendarId: familyCalendarId,
    }));

    // 単一の必須フィールドを落としただけでも拒否する。
    for (const missing of [
      "title", "startAt", "endAt", "allDay", "type", "memo",
      "updatedBy", "createdAt", "updatedAt", "deleted", "calendarId",
    ]) {
      const data = validEvent();
      delete data[missing];
      await assertFails(
          setDoc(doc(familyDb, `events/missing-${missing}`), data),
          `missing ${missing} should be rejected`,
      );
    }
  });

  it("型が不正な予定は作成できない（Issue #117）", async () => {
    const familyDb = dbFor("family-user");

    await assertFails(setDoc(doc(familyDb, "events/bad-start"), validEvent({
      startAt: "2026-07-20", // timestamp ではなく文字列
    })));
    await assertFails(setDoc(doc(familyDb, "events/bad-alldiff"), validEvent({
      allDay: "yes", // bool ではなく文字列
    })));
    await assertFails(setDoc(doc(familyDb, "events/bad-type"), validEvent({
      type: "maybe", // tentative / confirmed 以外
    })));
    await assertFails(setDoc(doc(familyDb, "events/bad-creator"), validEvent({
      creatorId: "", // 空文字は creatorId として無効（ownerId も無い）
    })));
    await assertFails(setDoc(doc(familyDb, "events/bad-recur"), validEvent({
      recurrenceFrequency: "daily", // 未対応の頻度
    })));
  });

  it("正当な予定は差分更新もソフト削除もできる（Issue #117）", async () => {
    const familyDb = dbFor("family-user");
    const event = doc(familyDb, "events/valid-1");

    await assertSucceeds(setDoc(event, validEvent()));
    // 編集（差分更新）: 変更フィールド + updatedBy / updatedAt のマージ後も正当。
    await assertSucceeds(updateDoc(event, {
      title: "タイトル変更",
      updatedBy: "family-user",
      updatedAt: serverTimestamp(),
    }));
    // ソフト削除。
    await assertSucceeds(updateDoc(event, {
      deleted: true,
      updatedBy: "family-user",
      updatedAt: serverTimestamp(),
    }));
  });

  it("既存の正当な予定を不正な形へ全置換で上書きできない（Issue #117）", async () => {
    // set（merge なし）は既存ドキュメントを丸ごと置き換えるため update 規則を通る。
    // 置換後の姿が不正なら拒否する（request.resource.data はマージ後の完全な姿）。
    const familyDb = dbFor("family-user");
    const event = doc(familyDb, "events/overwrite-1");

    await assertSucceeds(setDoc(event, validEvent()));
    await assertFails(setDoc(event, {
      title: "壊れた上書き",
      deleted: false,
      calendarId: familyCalendarId,
    }));
  });

  it("レガシー予定（旧フィールド名・欠落・旧形式）のソフト削除はできる（Issue #117）", async () => {
    // モデルが後方互換で読めるレガシー予定は Rules も拒否しない。
    // - creatorId ではなく旧 ownerId 名
    // - participantIds 欠落（参加者機能導入前）
    // - reminderOffsets が旧形式の number[]
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const legacy = validEvent();
      delete legacy.creatorId;
      delete legacy.participantIds;
      delete legacy.recurrenceFrequency;
      delete legacy.recurrenceCount;
      delete legacy.recurrenceExceptions;
      delete legacy.recurrenceUntil;
      legacy.ownerId = "family-user";
      legacy.reminderOffsets = [60];
      await setDoc(doc(context.firestore(), "events/legacy-valid"), legacy);
    });

    const event = doc(dbFor("family-user"), "events/legacy-valid");
    await assertSucceeds(updateDoc(event, {
      deleted: true,
      updatedBy: "family-user",
      updatedAt: serverTimestamp(),
    }));
  });

  it("家族ではない認証ユーザーと未認証ユーザーは events を利用できない", async () => {
    const outsiderEvent = doc(dbFor("outsider"), "events/event-1");
    const anonymousEvent = doc(
        testEnvironment.unauthenticatedContext().firestore(),
        "events/event-1",
    );

    await assertFails(getDoc(outsiderEvent));
    await assertFails(setDoc(outsiderEvent, {
      title: "Denied",
      calendarId: familyCalendarId,
    }));
    await assertFails(getDoc(anonymousEvent));
  });

  it("reminders は家族だけが読め、クライアントから書けない", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "reminders/reminder-1"), {
        eventId: "event-1",
      });
    });

    const familyReminder = doc(
        dbFor("family-user"),
        "reminders/reminder-1",
    );
    const outsiderReminder = doc(
        dbFor("outsider"),
        "reminders/reminder-1",
    );

    await assertSucceeds(getDoc(familyReminder));
    await assertFails(getDoc(outsiderReminder));
    await assertFails(setDoc(familyReminder, {eventId: "event-2"}));
  });

  it("devices は本人だけが読み書きできる", async () => {
    const ownDevice = doc(
        dbFor("family-user"),
        "users/family-user/devices/token-1",
    );
    const otherDevice = doc(
        dbFor("family-user"),
        "users/other-family-user/devices/token-1",
    );

    await assertSucceeds(setDoc(ownDevice, {platform: "ios"}));
    await assertSucceeds(getDoc(ownDevice));
    await assertFails(setDoc(otherDevice, {platform: "ios"}));
    await assertFails(getDoc(otherDevice));
  });

  it("calendarId を持たない予定は読み書きできない（FR-8 / Issue #93）", async () => {
    // 旧・既定カレンダー（'default'）へのフォールバックは廃止した。移行スクリプトで
    // 全予定に calendarId が実在するため、欠損は不正なドキュメントとして扱う。
    const familyDb = dbFor("family-user");

    await assertFails(setDoc(doc(familyDb, "events/no-calendar-event"), {
      title: "Legacy event",
      deleted: false,
    }));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "events/legacy-event"), {
        title: "Legacy event",
        deleted: false,
      });
    });

    await assertFails(getDoc(doc(familyDb, "events/legacy-event")));
    await assertFails(deleteDoc(doc(familyDb, "events/legacy-event")));
  });

  it("calendars は参加者だけが読み書きでき、非参加者は不可（FR-8）", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "calendars/solo"), {
        name: "自分専用",
        memberIds: ["family-user"],
        creatorId: "family-user",
      });
    });

    const memberDb = dbFor("family-user");
    const outsiderDb = dbFor("other-family-user");

    await assertSucceeds(getDoc(doc(memberDb, "calendars/solo")));
    await assertFails(getDoc(doc(outsiderDb, "calendars/solo")));
    await assertFails(setDoc(doc(outsiderDb, "calendars/solo"), {
      name: "乗っ取り",
      memberIds: ["other-family-user"],
    }));
  });

  it("calendars の作成は自分を含み、自分がオーナーの場合のみ許可する（FR-8 / Issue #89）", async () => {
    const familyDb = dbFor("family-user");

    await assertSucceeds(setDoc(doc(familyDb, "calendars/new-calendar"), {
      name: "新規カレンダー",
      memberIds: ["family-user"],
      creatorId: "family-user",
      ownerId: "family-user",
    }));
    await assertFails(setDoc(doc(familyDb, "calendars/no-self"), {
      name: "自分抜き",
      memberIds: ["other-family-user"],
      creatorId: "family-user",
      ownerId: "family-user",
    }));
    await assertFails(setDoc(doc(familyDb, "calendars/not-owner"), {
      name: "他人がオーナー",
      memberIds: ["family-user", "other-family-user"],
      creatorId: "family-user",
      ownerId: "other-family-user",
    }));
  });

  it("memberIds / ownerId はクライアントから書き換えられない（Issue #89）", async () => {
    // メンバーの追加・削除・オーナー移譲は Callable Function 経由のみ
    // （functions/membership.js）。Rules はクライアントの直接書き換えを拒否する。
    const ownerDb = dbFor("family-user");
    const memberDb = dbFor("other-family-user");

    await assertFails(updateDoc(doc(memberDb, `calendars/${familyCalendarId}`), {
      memberIds: ["other-family-user"],
    }));
    await assertFails(updateDoc(doc(ownerDb, `calendars/${familyCalendarId}`), {
      memberIds: ["family-user"],
    }));
    await assertFails(updateDoc(doc(memberDb, `calendars/${familyCalendarId}`), {
      ownerId: "other-family-user",
    }));
    await assertFails(updateDoc(doc(ownerDb, `calendars/${familyCalendarId}`), {
      ownerId: "other-family-user",
    }));
  });

  it("カレンダー名を変更できるのはオーナーだけ（Issue #89）", async () => {
    const ownerDb = dbFor("family-user");
    const memberDb = dbFor("other-family-user");

    // アプリの書き込み（CalendarRepository.updateName）と同じ形にする。
    await assertFails(updateDoc(doc(memberDb, `calendars/${familyCalendarId}`), {
      name: "勝手に改名",
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(ownerDb, `calendars/${familyCalendarId}`), {
      name: "わが家（改）",
      updatedAt: serverTimestamp(),
    }));
  });

  it("ownerId 欠損時は creatorId をオーナーとみなす（バックフィル前の後方互換）", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "calendars/legacy"), {
        name: "旧カレンダー",
        memberIds: ["family-user", "other-family-user"],
        creatorId: "family-user",
      });
    });

    await assertFails(updateDoc(doc(dbFor("other-family-user"), "calendars/legacy"), {
      name: "勝手に改名",
    }));
    await assertSucceeds(updateDoc(doc(dbFor("family-user"), "calendars/legacy"), {
      name: "旧カレンダー（改）",
    }));
  });

  it("既存のカレンダーに非メンバーは勝手に参加できない（特例廃止、FR-8）", async () => {
    const newMemberDb = dbFor("new-user");
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/new-user"), {
        name: "New User",
      });
    });

    // カレンダーに特別扱いされる ID は無く（Issue #87 / #93）、参加者だけが
    // 読み書きできる。自分を勝手に memberIds へ追加することもできない。
    await assertFails(getDoc(doc(newMemberDb, `calendars/${familyCalendarId}`)));
    await assertFails(setDoc(doc(newMemberDb, `calendars/${familyCalendarId}`), {
      name: "わが家",
      memberIds: ["family-user", "other-family-user", "new-user"],
      creatorId: "family-user",
    }, {merge: true}));
  });

  it("参加していないカレンダーの予定は読み書きできない（FR-8）", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "calendars/solo"), {
        name: "自分専用",
        memberIds: ["family-user"],
        creatorId: "family-user",
      });
      await setDoc(doc(context.firestore(), "events/solo-event"), {
        title: "自分専用の予定",
        deleted: false,
        calendarId: "solo",
      });
    });

    const memberDb = dbFor("family-user");
    const outsiderDb = dbFor("other-family-user");

    await assertSucceeds(getDoc(doc(memberDb, "events/solo-event")));
    await assertFails(getDoc(doc(outsiderDb, "events/solo-event")));
    await assertFails(setDoc(doc(outsiderDb, "events/solo-event"), {
      title: "Denied",
    }, {merge: true}));
    await assertFails(setDoc(doc(outsiderDb, "events/other-solo-event"), {
      title: "Denied",
      deleted: false,
      calendarId: "solo",
    }));
  });

  it("カレンダーIDで絞り込んだ一覧取得は、他カレンダーの予定を含めず拒否もされない（FR-8）", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "calendars/solo"), {
        name: "自分専用",
        memberIds: ["family-user"],
        creatorId: "family-user",
      });
      await setDoc(doc(context.firestore(), "events/family-event"), {
        title: "わが家の予定",
        deleted: false,
        calendarId: familyCalendarId,
      });
      await setDoc(doc(context.firestore(), "events/solo-event"), {
        title: "自分専用の予定",
        deleted: false,
        calendarId: "solo",
      });
    });

    const memberDb = dbFor("family-user");
    const familyQuery = query(
        collection(memberDb, "events"),
        where("calendarId", "==", familyCalendarId),
    );

    // calendarId を実クエリの where 句として絞り込んでいるため、
    // 他カレンダー（solo）の予定が同一コレクションに存在してもクエリ全体は
    // 拒否されず、絞り込んだカレンダーの予定だけが返る。
    const snapshot = await assertSucceeds(getDocs(familyQuery));
    const ids = snapshot.docs.map((d) => d.id);
    assert.deepStrictEqual(ids, ["family-event"]);
  });

  it("invites はメンバーでも読み書きできない（FR-9 / Issue #90）", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "invites/invite-1"), {
        calendarId: familyCalendarId,
        tokenHash: "hash",
        invitedBy: "family-user",
        maxUses: 1,
        usedCount: 0,
        revoked: false,
      });
    });

    // 発行者本人（かつカレンダーのオーナー）でも、クライアントからは触れない。
    // 発行・確認・受諾・取り消し・一覧はすべて Callable Function 経由（Admin SDK）。
    const memberDb = dbFor("family-user");
    await assertFails(getDoc(doc(memberDb, "invites/invite-1")));
    await assertFails(getDocs(collection(memberDb, "invites")));
    await assertFails(updateDoc(doc(memberDb, "invites/invite-1"), {
      revoked: true,
    }));
    await assertFails(deleteDoc(doc(memberDb, "invites/invite-1")));
    await assertFails(setDoc(doc(memberDb, "invites/invite-2"), {
      calendarId: familyCalendarId,
      tokenHash: "hash",
      invitedBy: "family-user",
    }));
  });

  it("招待の受諾を装った memberIds の追加はできない（FR-9 / Issue #90）", async () => {
    // memberIds はクライアントから書けない（Issue #89）。招待リンクを持っていても
    // 自力で参加はできず、Callable（acceptInvite）を通す必要がある。
    const outsiderDb = dbFor("outsider");
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/outsider"), {
        name: "Outsider",
      });
    });

    await assertFails(updateDoc(doc(outsiderDb, `calendars/${familyCalendarId}`), {
      memberIds: ["family-user", "other-family-user", "outsider"],
    }));
  });
});

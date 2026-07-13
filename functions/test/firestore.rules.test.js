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
    // FR-8: 既定カレンダー（わが家）。calendarId 未設定の予定はここに
    // 属するものとして扱う（firestore.rules の eventCalendarId 参照）。
    await setDoc(doc(context.firestore(), "calendars/default"), {
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

    await assertSucceeds(setDoc(event, {
      title: "Family event",
      deleted: false,
    }));
    await assertSucceeds(getDoc(event));
    await assertSucceeds(deleteDoc(event));
  });

  it("家族ではない認証ユーザーと未認証ユーザーは events を利用できない", async () => {
    const outsiderEvent = doc(dbFor("outsider"), "events/event-1");
    const anonymousEvent = doc(
        testEnvironment.unauthenticatedContext().firestore(),
        "events/event-1",
    );

    await assertFails(getDoc(outsiderEvent));
    await assertFails(setDoc(outsiderEvent, {title: "Denied"}));
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

  it("calendarId未設定の予定は既定カレンダーのメンバーとして読み書きできる（FR-8）", async () => {
    const event = doc(dbFor("family-user"), "events/legacy-event");

    await assertSucceeds(setDoc(event, {
      title: "Legacy event",
      deleted: false,
    }));
    await assertSucceeds(getDoc(event));
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

    await assertFails(updateDoc(doc(memberDb, "calendars/default"), {
      memberIds: ["other-family-user"],
    }));
    await assertFails(updateDoc(doc(ownerDb, "calendars/default"), {
      memberIds: ["family-user"],
    }));
    await assertFails(updateDoc(doc(memberDb, "calendars/default"), {
      ownerId: "other-family-user",
    }));
    await assertFails(updateDoc(doc(ownerDb, "calendars/default"), {
      ownerId: "other-family-user",
    }));
  });

  it("カレンダー名を変更できるのはオーナーだけ（Issue #89）", async () => {
    const ownerDb = dbFor("family-user");
    const memberDb = dbFor("other-family-user");

    // アプリの書き込み（CalendarRepository.updateName）と同じ形にする。
    await assertFails(updateDoc(doc(memberDb, "calendars/default"), {
      name: "勝手に改名",
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(ownerDb, "calendars/default"), {
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

  it("既定カレンダーにも非メンバーは参加できない（特例廃止、FR-8）", async () => {
    const newMemberDb = dbFor("new-user");
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/new-user"), {
        name: "New User",
      });
    });

    // 旧・既定カレンダー（'default'）は特別扱いをやめ、他のカレンダーと同じく
    // 参加者だけが読み書きできる。自分を勝手に追加することもできない。
    await assertFails(getDoc(doc(newMemberDb, "calendars/default")));
    await assertFails(setDoc(doc(newMemberDb, "calendars/default"), {
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
      await setDoc(doc(context.firestore(), "events/default-event"), {
        title: "わが家の予定",
        deleted: false,
        calendarId: "default",
      });
      await setDoc(doc(context.firestore(), "events/solo-event"), {
        title: "自分専用の予定",
        deleted: false,
        calendarId: "solo",
      });
    });

    const memberDb = dbFor("family-user");
    const defaultQuery = query(
        collection(memberDb, "events"),
        where("calendarId", "==", "default"),
    );

    // calendarId を実クエリの where 句として絞り込んでいるため、
    // 他カレンダー（solo）の予定が同一コレクションに存在してもクエリ全体は
    // 拒否されず、絞り込んだカレンダーの予定だけが返る。
    const snapshot = await assertSucceeds(getDocs(defaultQuery));
    const ids = snapshot.docs.map((d) => d.id);
    assert.deepStrictEqual(ids, ["default-event"]);
  });
});

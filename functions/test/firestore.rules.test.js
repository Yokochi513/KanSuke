"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
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
  it("家族メンバーは users を読めて自分の情報だけを書ける", async () => {
    const familyDb = dbFor("family-user");

    await assertSucceeds(getDoc(doc(familyDb, "users/other-family-user")));
    await assertSucceeds(setDoc(doc(familyDb, "users/family-user"), {
      name: "Updated",
    }));
    await assertFails(setDoc(doc(familyDb, "users/other-family-user"), {
      name: "Denied",
    }));
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
});

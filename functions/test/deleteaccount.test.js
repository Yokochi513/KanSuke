"use strict";

const assert = require("node:assert");
const {deleteAccount} = require("../deleteaccount");

const serverTimestamp = () => "SERVER_TS";

// Firestore（Admin SDK）を模した最小フェイク。
//
// ドキュメントはフルパス（"collection/id" や "users/uid/devices/token"）を
// キーにフラットな map で保持する。コレクション参照は「そのパスの直下（残り 1
// セグメント）」に一致するドキュメントを対象にし、`where` は "==" と
// "array-contains" を解釈する。batch / doc.update / doc.delete をその場で反映する。
function fakeDb(seed) {
  const store = {...seed};

  function docRef(path) {
    return {
      path,
      get id() {
        const parts = path.split("/");
        return parts[parts.length - 1];
      },
      async get() {
        const data = store[path];
        return {exists: data !== undefined, id: this.id, data: () => data};
      },
      async delete() {
        delete store[path];
      },
      async update(patch) {
        if (store[path] === undefined) {
          throw new Error(`update on missing doc: ${path}`);
        }
        store[path] = {...store[path], ...patch};
      },
    };
  }

  function matchingDocs(collectionPath, predicate) {
    const prefix = `${collectionPath}/`;
    return Object.keys(store)
      .filter(
        (path) =>
          path.startsWith(prefix) &&
          !path.slice(prefix.length).includes("/"),
      )
      .filter((path) => predicate(store[path]))
      .map((path) => {
        const ref = docRef(path);
        return {id: ref.id, ref, data: () => store[path]};
      });
  }

  function query(collectionPath, predicate) {
    return {
      where(field, op, value) {
        return query(collectionPath, (data) => {
          if (!predicate(data)) return false;
          if (op === "==") return data[field] === value;
          if (op === "array-contains") {
            return Array.isArray(data[field]) && data[field].includes(value);
          }
          throw new Error(`unsupported op: ${op}`);
        });
      },
      async get() {
        const docs = matchingDocs(collectionPath, predicate);
        return {docs, size: docs.length};
      },
    };
  }

  return {
    store,
    collection(path) {
      return query(path, () => true);
    },
    doc(path) {
      return docRef(path);
    },
    batch() {
      const ops = [];
      return {
        delete(ref) {
          ops.push(ref);
        },
        async commit() {
          for (const ref of ops) {
            await ref.delete();
          }
        },
      };
    },
  };
}

// Admin Auth を模したフェイク。deleteUser の呼び出しを記録し、指定した uid を
// 「既に存在しない」ものとして user-not-found を投げられるようにする。
function fakeAuth({missing = []} = {}) {
  const deleted = [];
  return {
    deleted,
    async deleteUser(uid) {
      if (missing.includes(uid)) {
        const error = new Error("no user");
        error.code = "auth/user-not-found";
        throw error;
      }
      deleted.push(uid);
    },
  };
}

async function assertHttpsError(code, run) {
  await assert.rejects(run, (error) => {
    assert.strictEqual(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

// 個人カレンダー 1 つ・その予定 1 件・その予定のリマインド 1 件・本人のデバイス
// 1 台・本人のドキュメント、を持つ最小の退会前状態。
function soloSeed() {
  return {
    "users/me": {name: "ぱぱ", email: "me@example.com", color: "#1565C0"},
    "users/me/devices/token-a": {platform: "ios"},
    "calendars/solo": {
      name: "ぱぱのカレンダー",
      memberIds: ["me"],
      creatorId: "me",
      ownerId: "me",
    },
    "events/e1": {title: "通院", calendarId: "solo", creatorId: "me"},
    "reminders/r1": {eventId: "e1", ownerId: "me", sent: false},
    "invites/i1": {calendarId: "solo", invitedBy: "me"},
  };
}

describe("deleteAccount（Issue #102）", function() {
  it("本人のみのカレンダーと予定・リマインド・招待・ユーザーを削除し、"+
    "最後に Auth ユーザーを削除する", async function() {
    const db = fakeDb(soloSeed());
    const auth = fakeAuth();

    await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);

    for (const path of [
      "calendars/solo",
      "events/e1",
      "reminders/r1",
      "invites/i1",
      "users/me/devices/token-a",
      "users/me",
    ]) {
      assert.strictEqual(db.store[path], undefined, `${path} は消えているはず`);
    }
    assert.deepStrictEqual(auth.deleted, ["me"]);
  });

  it("共有カレンダー（本人は非オーナー）からは退出扱いになり、"+
    "カレンダーと予定は残る", async function() {
    const db = fakeDb({
      "users/me": {name: "ぱぱ"},
      "calendars/shared": {
        name: "わが家",
        memberIds: ["owner", "me"],
        creatorId: "owner",
        ownerId: "owner",
      },
      "events/shared-e": {title: "旅行", calendarId: "shared", creatorId: "me"},
    });
    const auth = fakeAuth();

    await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);

    assert.deepStrictEqual(
      db.store["calendars/shared"].memberIds,
      ["owner"],
    );
    assert.strictEqual(db.store["calendars/shared"].ownerId, "owner");
    assert.strictEqual(db.store["calendars/shared"].updatedAt, "SERVER_TS");
    // 共有予定は残す（他メンバーの表示を壊さない）。
    assert.notStrictEqual(db.store["events/shared-e"], undefined);
  });

  it("本人がオーナーの共有カレンダーは、本人以外の先頭メンバーへ"+
    "オーナーを移譲してから退出する", async function() {
    const db = fakeDb({
      "users/me": {name: "ぱぱ"},
      "calendars/shared": {
        name: "わが家",
        memberIds: ["me", "child", "mama"],
        creatorId: "me",
        ownerId: "me",
      },
    });
    const auth = fakeAuth();

    await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);

    assert.deepStrictEqual(
      db.store["calendars/shared"].memberIds,
      ["child", "mama"],
    );
    assert.strictEqual(db.store["calendars/shared"].ownerId, "child");
  });

  it("共有予定に本人が付けたリマインドも削除する（ownerId で引く）",
    async function() {
      const db = fakeDb({
        "users/me": {name: "ぱぱ"},
        "calendars/shared": {
          name: "わが家",
          memberIds: ["owner", "me"],
          creatorId: "owner",
          ownerId: "owner",
        },
        "events/shared-e": {title: "旅行", calendarId: "shared"},
        // 共有予定に本人が付けたリマインド（本人のみ削除対象）。
        "reminders/mine": {eventId: "shared-e", ownerId: "me", sent: false},
        // 他メンバーのリマインドは残す。
        "reminders/theirs": {
          eventId: "shared-e",
          ownerId: "owner",
          sent: false,
        },
      });
      const auth = fakeAuth();

      await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);

      assert.strictEqual(db.store["reminders/mine"], undefined);
      assert.notStrictEqual(db.store["reminders/theirs"], undefined);
    });

  it("他人が発行した招待・他人のカレンダーには手を出さない", async function() {
    const db = fakeDb({
      "users/me": {name: "ぱぱ"},
      "calendars/solo": {
        name: "ぱぱのカレンダー",
        memberIds: ["me"],
        creatorId: "me",
        ownerId: "me",
      },
      // 本人が参加していないカレンダー（array-contains に一致しない）。
      "calendars/other": {
        name: "他人",
        memberIds: ["stranger"],
        creatorId: "stranger",
        ownerId: "stranger",
      },
      "invites/mine": {calendarId: "solo", invitedBy: "me"},
      "invites/theirs": {calendarId: "other", invitedBy: "stranger"},
    });
    const auth = fakeAuth();

    await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);

    assert.notStrictEqual(db.store["calendars/other"], undefined);
    assert.strictEqual(db.store["invites/mine"], undefined);
    assert.notStrictEqual(db.store["invites/theirs"], undefined);
  });

  it("未サインインは unauthenticated になる", async function() {
    await assertHttpsError("unauthenticated", () => deleteAccount(
      fakeDb(soloSeed()),
      fakeAuth(),
      {uid: null},
      serverTimestamp,
    ));
  });

  it("再実行しても壊れない（冪等）", async function() {
    const db = fakeDb(soloSeed());
    const auth = fakeAuth();

    await deleteAccount(db, auth, {uid: "me"}, serverTimestamp);
    // 2 回目: Firestore は空振り、Auth は user-not-found を握りつぶす。
    const auth2 = fakeAuth({missing: ["me"]});
    await deleteAccount(db, auth2, {uid: "me"}, serverTimestamp);

    assert.deepStrictEqual(auth2.deleted, []);
    assert.strictEqual(db.store["users/me"], undefined);
  });
});

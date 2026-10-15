"use strict";

// サインアップ時の初期データ生成ロジック（基本設計 §2.1 / FR-8）。
// Firestore/Functions に依存しない純粋関数にして単体テスト可能にする。

/**
 * メンバー識別色の候補（FR-2）。`lib/app/theme.dart` の
 * `MemberColors.palette` と対応させる。
 */
const memberColors = [
  "#1B4B72", // 藍
  "#B7412E", // 朱
  "#3F6B3A", // 松葉
  "#5B3E7E", // 紫紺
  "#B4506E", // 紅梅
  "#D9A62E", // 山吹
];

/**
 * サインインメールを小文字・トリムして正規化する。
 * @param {?string} email
 * @return {string}
 */
function normalizeEmail(email) {
  return (email || "").trim().toLowerCase();
}

/**
 * 表示名を決める。ID プロバイダの表示名を優先し、無ければメールのローカル部を使う。
 *
 * @param {?string} displayName
 * @param {string} email 正規化済みのメール。
 * @return {string}
 */
function resolveName(displayName, email) {
  const name = (displayName || "").trim();
  if (name) return name;
  const localPart = email.split("@")[0];
  return localPart || "メンバー";
}

/**
 * 識別色を割り当てる（FR-2）。uid から決定的に選ぶだけの初期値で、
 * 本人が設定画面でいつでも変更できるため、重複しても支障はない。
 *
 * @param {string} uid
 * @return {string}
 */
function pickColor(uid) {
  let hash = 0;
  for (const character of String(uid)) {
    hash = (hash + character.codePointAt(0)) % memberColors.length;
  }
  return memberColors[hash];
}

/**
 * `users/{uid}` の初期プロフィールを組み立てる。
 *
 * Issue #183: メールアドレスは Firestore に保存しない。`users/{uid}` は
 * 「同じカレンダーに同席したことのある相手なら uid を知っている限り読める」
 * （`allow get: if isRegistered()`）ため、保存すると一度共有しただけの相手に
 * メールが恒久的に渡ってしまう。正典は Firebase Auth 側であり、サーバーで
 * 必要になったときは `admin.auth().getUser(uid)` で取得できる。
 * ここでは表示名の導出（プロバイダ表示名が無いときのローカル部）にだけ使う。
 *
 * @param {{uid: string, email?: string, displayName?: string}} user
 * @return {{name: string, color: string}}
 */
function buildInitialProfile(user) {
  const email = normalizeEmail(user.email);
  return {
    name: resolveName(user.displayName, email),
    color: pickColor(user.uid),
  };
}

/**
 * 個人カレンダー（本人だけが参加するカレンダー）の名前を組み立てる（FR-8）。
 *
 * @param {string} name 表示名。
 * @return {string}
 */
function personalCalendarName(name) {
  return `${name}のカレンダー`;
}

module.exports = {
  buildInitialProfile,
  memberColors,
  normalizeEmail,
  personalCalendarName,
};

"use strict";

// 簡易レートリミット（Issue #103）。
//
// uid 単位の固定ウィンドウカウンタ。Cloud Functions のインスタンスは複数・
// 使い捨てなので、これは**インスタンス内のベストエフォート**であり厳密な上限
// ではない。狙いは「壊れたスクリプトが無制限に Firestore を読み続けるのを
// その場で止める」ことで、家庭内利用ではこれで足りる（厳密な制御が要るように
// なったら Firestore ベースのカウンタへ移す）。

const {ApiError} = require("./errors");

const DEFAULT_LIMIT = 120;
const DEFAULT_WINDOW_MS = 60 * 1000;

/**
 * uid 単位のレートリミッタを作る。
 *
 * @param {{limit?: number, windowMs?: number}} options 上限とウィンドウ幅。
 * @return {{check: function(string, Date): void}}
 */
function createRateLimiter(options = {}) {
  const limit = options.limit || DEFAULT_LIMIT;
  const windowMs = options.windowMs || DEFAULT_WINDOW_MS;
  const buckets = new Map();

  return {
    /**
     * 1 リクエストを計上し、上限超過なら 429 を投げる。
     *
     * @param {string} uid 呼び出し元。
     * @param {Date} now 現在時刻。
     * @return {void}
     */
    check(uid, now) {
      const nowMs = now.getTime();
      // ウィンドウを跨いだ古いバケットは、uid が増え続けても
      // メモリが伸びないようここで捨てる。
      for (const [key, bucket] of buckets) {
        if (nowMs - bucket.startedAt >= windowMs) buckets.delete(key);
      }

      const bucket = buckets.get(uid);
      if (!bucket) {
        buckets.set(uid, {startedAt: nowMs, count: 1});
        return;
      }
      bucket.count += 1;
      if (bucket.count > limit) {
        throw new ApiError(
          "resource_exhausted",
          "リクエストが多すぎます。しばらく待って再試行してください。",
        );
      }
    },
  };
}

module.exports = {DEFAULT_LIMIT, DEFAULT_WINDOW_MS, createRateLimiter};

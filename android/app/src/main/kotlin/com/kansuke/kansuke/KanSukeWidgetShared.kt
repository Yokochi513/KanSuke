package com.kansuke.kansuke

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/**
 * リスト（[KanSukeWidgetProvider]）と月表示（[KanSukeMonthWidgetProvider]）の
 * 2 つのウィジェットで共有する定数と小道具（Issue #127）。
 */
internal object KanSukeWidget {

    /** Flutter 側 `homeWidgetPayloadKey` と揃える。 */
    const val PAYLOAD_KEY = "kansuke.widget.payload"

    /** Flutter 側 `homeWidgetPayloadVersion` と揃える。 */
    const val PAYLOAD_VERSION = 2

    /** 識別色を引けなかったときの色（Flutter 側 `homeWidgetFallbackColor` と同じ）。 */
    const val FALLBACK_COLOR = 0xFF9E9E9E.toInt()

    /** 日曜始まりの曜日名。DayOfWeek（月=1〜日=7）を `% 7` で引く。 */
    val WEEKDAYS = arrayOf("日", "月", "火", "水", "木", "金", "土")

    private const val LAUNCH_TEMPLATE_REQUEST_CODE = 1

    /**
     * Flutter 側が書き込んだペイロード。まだ無い・壊れている場合は null。
     *
     * 版が食い違う場合も null ではなくそのまま返し、呼び出し側が「アプリを再起動」
     * の案内を出せるようにする。
     */
    fun readPayload(context: Context): JSONObject? {
        val raw = HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (error: RuntimeException) {
            null
        }
    }

    /**
     * コレクション（ListView / GridView）の行タップ用テンプレート。
     *
     * テンプレートは fill-in intent を合成するため mutable が要る
     * （[HomeWidgetLaunchIntent.getActivity] は immutable を返すのでヘッダー専用）。
     * ヘッダー側（requestCode 0）と番号を分け、同じ PendingIntent を上書きしない。
     */
    fun launchTemplate(context: Context): PendingIntent {
        val intent =
            Intent(context, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getActivity(context, LAUNCH_TEMPLATE_REQUEST_CODE, intent, flags)
    }

    /** `#RRGGBB` を色へ。読めない値は [FALLBACK_COLOR]。 */
    fun parseColor(hex: String?): Int {
        if (hex.isNullOrEmpty()) return FALLBACK_COLOR
        return try {
            Color.parseColor(hex)
        } catch (error: RuntimeException) {
            FALLBACK_COLOR
        }
    }

    /**
     * [background] の上に重ねても読める文字色（黒 or 白）。
     *
     * 識別色もまとめ帯の地色も設定で自由に変えられるため（FR-2 / Issue #112）、
     * 固定の文字色だと明るい地色で白文字が埋もれる。アプリ側の `readableTextColor`
     * と同じ判定（相対輝度 0.15 を境に黒/白）にして、見え方を揃える。
     */
    fun readableTextColor(background: Int): Int =
        if (relativeLuminance(background) > 0.15) Color.BLACK else Color.WHITE

    /** sRGB の相対輝度（WCAG）。Flutter の `Color.computeLuminance` と同じ式。 */
    private fun relativeLuminance(color: Int): Double {
        fun channel(value: Int): Double {
            val srgb = value / 255.0
            return if (srgb <= 0.03928) srgb / 12.92
            else Math.pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(Color.red(color)) +
            0.7152 * channel(Color.green(color)) +
            0.0722 * channel(Color.blue(color))
    }
}

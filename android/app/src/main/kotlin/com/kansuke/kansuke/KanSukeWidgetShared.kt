package com.kansuke.kansuke

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
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
     * 設定「ウィジェットの外観」。
     *
     * 版の確認より前に読む。版が食い違って「アプリを再起動してください」を出す
     * ときも、選んだ外観で描けるようにするため。
     */
    fun readAppearance(context: Context): WidgetTheme =
        WidgetTheme(context, WidgetAppearance.of(readPayload(context)?.optString("appearance")))

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

/** 設定「ウィジェットの外観」。Flutter 側 `WidgetAppearance` と名前を揃える。 */
internal enum class WidgetAppearance(val key: String) {
    /** 端末のダークモード設定に従う（既定）。 */
    SYSTEM("system"),

    /** 和紙（ライト）で固定する。 */
    LIGHT("light"),

    /** 墨（ダーク）で固定する。 */
    DARK("dark"),

    /** 地を敷かず壁紙を透かす。文字色は端末のダークモード設定に従う。 */
    TRANSPARENT("transparent");

    companion object {
        /** 保存済みの文字列を戻す。未保存・未知の値は [SYSTEM]。 */
        fun of(key: String?): WidgetAppearance = entries.firstOrNull { it.key == key } ?: SYSTEM
    }
}

/**
 * 外観の設定に応じた配色（Issue #127 フォローアップ）。
 *
 * RemoteViews のレイアウトとドローアブルはランチャー側のプロセスで解決されるため、
 * XML に書いた `@color/widget_*`（values-night つき）は**端末のダークモード設定**で
 * 決まり、アプリの設定では動かせない。そこでライト/ダークに固定するときだけ、色を
 * この場で決めて RemoteViews へ明示的に流し込み、ドローアブルも固定版へ差し替える。
 *
 * 「システム追従」「透過」のときは文字色を触らない（[overrides] が false）。XML の
 * 既定に任せておけば、端末のダークモードが切り替わった瞬間にランチャー側で追従して
 * くれるため（明示した色は次の更新まで古いままになる）。
 */
internal class WidgetTheme(
    private val context: Context,
    val appearance: WidgetAppearance,
) {

    /** レイアウトに書かれた色を上書きするか。ライト/ダーク固定のときだけ true。 */
    val overrides: Boolean =
        appearance == WidgetAppearance.LIGHT || appearance == WidgetAppearance.DARK

    /** ダークの配色で描くか。追従・透過のときは端末のダークモード設定を見る。 */
    private val dark: Boolean =
        when (appearance) {
            WidgetAppearance.LIGHT -> false
            WidgetAppearance.DARK -> true
            WidgetAppearance.SYSTEM,
            WidgetAppearance.TRANSPARENT ->
                (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
        }

    val background: Int
        get() = color(R.color.widget_background_light, R.color.widget_background_dark)

    val text: Int
        get() = color(R.color.widget_text_light, R.color.widget_text_dark)

    val textSubtle: Int
        get() = color(R.color.widget_text_subtle_light, R.color.widget_text_subtle_dark)

    val accent: Int
        get() = color(R.color.widget_accent_light, R.color.widget_accent_dark)

    val outside: Int
        get() = color(R.color.widget_outside_light, R.color.widget_outside_dark)

    val sunday: Int
        get() = color(R.color.widget_sunday_light, R.color.widget_sunday_dark)

    val saturday: Int
        get() = color(R.color.widget_saturday_light, R.color.widget_saturday_dark)

    val mergedBar: Int
        get() = color(R.color.widget_merged_bar_light, R.color.widget_merged_bar_dark)

    /** 月表示の 1 マス（罫線）。 */
    val cellRes: Int
        get() =
            pickDrawable(
                R.drawable.kansuke_widget_cell,
                R.drawable.kansuke_widget_cell_light,
                R.drawable.kansuke_widget_cell_dark,
            )

    /** 今日のマス（罫線＋薄い地）。 */
    val cellTodayRes: Int
        get() =
            pickDrawable(
                R.drawable.kansuke_widget_cell_today,
                R.drawable.kansuke_widget_cell_today_light,
                R.drawable.kansuke_widget_cell_today_dark,
            )

    /** 今日の日付を囲む丸。 */
    val dayTodayRes: Int
        get() =
            pickDrawable(
                R.drawable.kansuke_widget_day_today,
                R.drawable.kansuke_widget_day_today_light,
                R.drawable.kansuke_widget_day_today_dark,
            )

    /** 「仮」バッジの枠。 */
    val tentativeRes: Int
        get() =
            pickDrawable(
                R.drawable.kansuke_widget_tentative,
                R.drawable.kansuke_widget_tentative_light,
                R.drawable.kansuke_widget_tentative_dark,
            )

    /**
     * 外枠の地を敷く。透過はドローアブルを外して壁紙を見せる。
     *
     * 外観を切り替えたときに前の地が残らないよう、どの外観でも必ず設定する。
     */
    fun applyBackground(views: RemoteViews, viewId: Int) {
        val backgroundRes =
            when (appearance) {
                WidgetAppearance.TRANSPARENT -> 0
                WidgetAppearance.LIGHT -> R.drawable.kansuke_widget_background_light
                WidgetAppearance.DARK -> R.drawable.kansuke_widget_background_dark
                WidgetAppearance.SYSTEM -> R.drawable.kansuke_widget_background
            }
        views.setInt(viewId, "setBackgroundResource", backgroundRes)
    }

    /** [overrides] のときだけ文字色を差し替える。 */
    fun applyTextColor(views: RemoteViews, viewId: Int, color: Int) {
        if (overrides) views.setTextColor(viewId, color)
    }

    private fun color(lightRes: Int, darkRes: Int): Int =
        ContextCompat.getColor(context, if (dark) darkRes else lightRes)

    /** 追従・透過は values-night 任せの素のドローアブル、固定なら専用版。 */
    private fun pickDrawable(systemRes: Int, lightRes: Int, darkRes: Int): Int =
        if (!overrides) systemRes else if (dark) darkRes else lightRes
}

package com.kansuke.kansuke

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject

/**
 * ホーム画面ウィジェットの一覧を供給するサービス（Issue #127）。
 *
 * Flutter 側（HomeWidgetSync）が書き込んだ JSON を読み、**描画時の日付**で今日と
 * 明日の行を組み立てる。日付をここで決めるので、アプリを何日か開かなくても
 * 見出しと中身が繰り上がる（JSON には数日分が入っている）。
 */
class KanSukeWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        KanSukeWidgetFactory(applicationContext)
}

/** ウィジェットの 1 行。 */
private sealed interface WidgetRow {
    /** 「今日 7/28(火)」の見出し。 */
    data class DayHeader(val label: String) : WidgetRow

    /** 「予定はありません」等の案内。 */
    data class Note(val text: String) : WidgetRow

    /** 予定 1 件。 */
    data class Entry(
        val title: String,
        val time: String,
        val colors: List<Int>,
        val tentative: Boolean,
    ) : WidgetRow
}

class KanSukeWidgetFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private var rows: List<WidgetRow> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        rows = buildRows()
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        return when (val row = rows.getOrNull(position)) {
            is WidgetRow.DayHeader -> dayHeaderViews(row)
            is WidgetRow.Entry -> entryViews(row)
            is WidgetRow.Note -> noteViews(row.text)
            // 行の入れ替えと描画がずれた瞬間に落ちないよう、空の案内でしのぐ。
            null -> noteViews("")
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = VIEW_TYPE_COUNT

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun dayHeaderViews(row: WidgetRow.DayHeader): RemoteViews =
        RemoteViews(context.packageName, R.layout.kansuke_widget_day_header).apply {
            setTextViewText(R.id.widget_day_header, row.label)
        }

    private fun noteViews(text: String): RemoteViews =
        RemoteViews(context.packageName, R.layout.kansuke_widget_note).apply {
            setTextViewText(R.id.widget_note, text)
        }

    private fun entryViews(row: WidgetRow.Entry): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.kansuke_widget_item)
        // FR-2: 参加者ごとの識別色。層は固定 3 つで、余った枠は畳む。
        DOT_IDS.forEachIndexed { index, viewId ->
            val color = row.colors.getOrNull(index)
            if (color == null) {
                views.setViewVisibility(viewId, View.GONE)
            } else {
                views.setViewVisibility(viewId, View.VISIBLE)
                views.setInt(viewId, "setColorFilter", color)
            }
        }
        views.setTextViewText(R.id.widget_item_time, row.time)
        views.setTextViewText(R.id.widget_item_title, row.title)
        // FR-3: 仮の予定だけ「仮」バッジを出す。
        views.setViewVisibility(
            R.id.widget_item_tentative,
            if (row.tentative) View.VISIBLE else View.GONE,
        )
        // タップでアプリを開く（テンプレートは KanSukeWidgetProvider が設定済み）。
        views.setOnClickFillInIntent(R.id.widget_item_root, Intent())
        return views
    }

    private fun buildRows(): List<WidgetRow> {
        val raw = HomeWidgetPlugin.getData(context).getString(PAYLOAD_KEY, null)
            ?: return listOf(note(R.string.kansuke_widget_open_app))
        val payload =
            try {
                JSONObject(raw)
            } catch (error: RuntimeException) {
                return listOf(note(R.string.kansuke_widget_open_app))
            }
        // アプリだけ先に更新されて、ウィジェットのプロセスが古いまま動くことがある。
        // 解釈できない版は崩れた表示を出さず、再起動を促す。
        if (payload.optInt("version") != PAYLOAD_VERSION) {
            return listOf(note(R.string.kansuke_widget_update_app))
        }
        if (!payload.optBoolean("signedIn", false)) {
            return listOf(note(R.string.kansuke_widget_signed_out))
        }

        val entriesByDate = mutableMapOf<String, JSONArray>()
        val days = payload.optJSONArray("days") ?: JSONArray()
        for (index in 0 until days.length()) {
            val day = days.optJSONObject(index) ?: continue
            val date = day.optString("date")
            if (date.isEmpty()) continue
            entriesByDate[date] = day.optJSONArray("entries") ?: JSONArray()
        }

        val today = LocalDate.now()
        val rows = mutableListOf<WidgetRow>()
        listOf(
            today to R.string.kansuke_widget_today,
            today.plusDays(1) to R.string.kansuke_widget_tomorrow,
        )
            .forEach { (date, labelRes) ->
                rows += WidgetRow.DayHeader(context.getString(labelRes, formatDate(date)))
                // LocalDate.toString() は ISO（yyyy-MM-dd）で、Flutter 側のキーと一致する。
                val entries = entriesByDate[date.toString()]
                when {
                    // 数日分を渡しているので、ここに来るのは書き込み前だけ。
                    entries == null -> rows += note(R.string.kansuke_widget_open_app)
                    entries.length() == 0 -> rows += note(R.string.kansuke_widget_empty)
                    else -> rows += parseEntries(entries)
                }
            }
        return rows
    }

    private fun parseEntries(entries: JSONArray): List<WidgetRow> {
        val parsed = mutableListOf<WidgetRow>()
        for (index in 0 until entries.length()) {
            val entry = entries.optJSONObject(index) ?: continue
            parsed +=
                WidgetRow.Entry(
                    title = entry.optString("title"),
                    time = entry.optString("time"),
                    colors = parseColors(entry.optJSONArray("colors")),
                    tentative = entry.optBoolean("tentative", false),
                )
        }
        return parsed
    }

    private fun parseColors(colors: JSONArray?): List<Int> {
        if (colors == null) return emptyList()
        val parsed = mutableListOf<Int>()
        for (index in 0 until minOf(colors.length(), DOT_IDS.size)) {
            parsed +=
                try {
                    Color.parseColor(colors.optString(index))
                } catch (error: RuntimeException) {
                    // 識別色を引けない参加者（退会済みなど）は Flutter 側でグレーに
                    // 寄せているが、想定外の文字列でも表示を止めない。
                    FALLBACK_COLOR
                }
        }
        return parsed
    }

    private fun note(resId: Int): WidgetRow.Note = WidgetRow.Note(context.getString(resId))

    /** 「7/28(火)」。曜日は DayOfWeek（月=1〜日=7）を日曜始まりの配列へ写す。 */
    private fun formatDate(date: LocalDate): String {
        val weekday = WEEKDAYS[date.dayOfWeek.value % WEEKDAYS.size]
        return "${date.monthValue}/${date.dayOfMonth}($weekday)"
    }

    private companion object {
        /** Flutter 側 `homeWidgetPayloadKey` と揃える。 */
        const val PAYLOAD_KEY = "kansuke.widget.payload"

        /** Flutter 側 `homeWidgetPayloadVersion` と揃える。 */
        const val PAYLOAD_VERSION = 1

        const val VIEW_TYPE_COUNT = 3

        const val FALLBACK_COLOR = 0xFF9E9E9E.toInt()

        val DOT_IDS =
            intArrayOf(
                R.id.widget_item_dot_1,
                R.id.widget_item_dot_2,
                R.id.widget_item_dot_3,
            )

        val WEEKDAYS = arrayOf("日", "月", "火", "水", "木", "金", "土")
    }
}

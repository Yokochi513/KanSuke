package com.kansuke.kansuke

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import java.time.DayOfWeek
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject

/**
 * 月表示ウィジェットのマスを供給するサービス（Issue #127、FR-4）。
 *
 * Flutter 側（HomeWidgetSync）が書き込んだ JSON を読み、**描画時の日付**の月で
 * グリッド（日曜始まり・4〜6 週）を組み立てる。月をここで決めるので、アプリを
 * 開かないまま月をまたいでもグリッドが繰り上がる（JSON は今月と翌月のグリッドを
 * 覆う範囲を持つ）。
 */
class KanSukeMonthWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        KanSukeMonthWidgetFactory(applicationContext)
}

/** マスに積む予定 1 件。 */
private data class MonthChip(val title: String, val color: Int, val tentative: Boolean)

/** グリッドの 1 マス。 */
private data class MonthCell(
    val date: LocalDate,
    /** 表示中の月の日か（前後月の日は淡く描く）。 */
    val inMonth: Boolean,
    val isToday: Boolean,
    val holiday: String?,
    val chips: List<MonthChip>,
    /** その日の全件数。マスに収まらないぶんを「+N」に集約するのに使う。 */
    val total: Int,
)

class KanSukeMonthWidgetFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var cells: List<MonthCell> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        cells = buildCells()
    }

    override fun onDestroy() {
        cells = emptyList()
    }

    override fun getCount(): Int = cells.size

    override fun getViewAt(position: Int): RemoteViews {
        val cell = cells.getOrNull(position)
        val views = RemoteViews(context.packageName, R.layout.kansuke_month_widget_cell)
        if (cell == null) return views

        views.setInt(
            R.id.month_cell_root,
            "setBackgroundResource",
            if (cell.isToday) R.drawable.kansuke_widget_cell_today else R.drawable.kansuke_widget_cell,
        )

        views.setTextViewText(R.id.month_cell_day, cell.date.dayOfMonth.toString())
        views.setTextColor(R.id.month_cell_day, dayNumberColor(cell))
        // FR-4: 今日は日付を丸で囲む（アプリの月表示と同じ目印）。
        if (cell.isToday) {
            views.setInt(
                R.id.month_cell_day,
                "setBackgroundResource",
                R.drawable.kansuke_widget_day_today,
            )
            views.setTextColor(R.id.month_cell_day, color(R.color.widget_background))
        } else {
            views.setInt(R.id.month_cell_day, "setBackgroundResource", 0)
        }

        if (cell.holiday == null) {
            views.setViewVisibility(R.id.month_cell_holiday, View.GONE)
        } else {
            views.setViewVisibility(R.id.month_cell_holiday, View.VISIBLE)
            views.setTextViewText(R.id.month_cell_holiday, cell.holiday)
        }

        bindChips(views, cell)
        // タップでアプリを開く（テンプレートは KanSukeMonthWidgetProvider が設定済み）。
        views.setOnClickFillInIntent(R.id.month_cell_root, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    /**
     * マスへ予定の帯を積む。
     *
     * 帯は固定 [CHIP_IDS] 本ぶんしか置けない。収まらない件数がある場合は、
     * **最後の 1 枠を「+N」に明け渡す**（アプリの月表示と同じで、「+N」もレーンを
     * 1 本使う）。こうするとマスの高さが帯 [CHIP_IDS] 本ぶんで頭打ちになり、
     * 4x5 のウィジェットに 6 週の月でも収まる。
     *
     * 並びは Flutter 側で日別一覧と同じ順に整列済みなので、上から順に置くだけでよい。
     */
    private fun bindChips(views: RemoteViews, cell: MonthCell) {
        val overflows = cell.total > CHIP_IDS.size
        val shown =
            if (overflows) CHIP_IDS.size - 1 else minOf(cell.chips.size, CHIP_IDS.size)
        CHIP_IDS.forEachIndexed { index, viewId ->
            val chip = cell.chips.getOrNull(index)
            if (chip == null || index >= shown) {
                views.setViewVisibility(viewId, View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(viewId, View.VISIBLE)
            views.setTextViewText(viewId, chip.title)
            // FR-2 の識別色で塗り、FR-3 の仮予定は同じ色の薄い塗りにして確定と
            // 区別する（アプリの月表示は枠線で区別しているが、角丸ドローアブルを
            // 実行時に着色する手段が API 31 未満に無いため、濃淡で置き換えている）。
            if (chip.tentative) {
                views.setInt(viewId, "setBackgroundColor", tentativeFill(chip.color))
                views.setTextColor(viewId, color(R.color.widget_text))
            } else {
                views.setInt(viewId, "setBackgroundColor", chip.color)
                views.setTextColor(viewId, KanSukeWidget.readableTextColor(chip.color))
            }
        }

        val hidden = cell.total - shown
        if (hidden > 0) {
            views.setViewVisibility(R.id.month_cell_more, View.VISIBLE)
            views.setTextViewText(
                R.id.month_cell_more,
                context.getString(R.string.kansuke_month_widget_more, hidden),
            )
        } else {
            views.setViewVisibility(R.id.month_cell_more, View.GONE)
        }
    }

    /** 仮の予定の地色（識別色を薄く敷く）。文字は通常の文字色のまま読める濃さにする。 */
    private fun tentativeFill(color: Int): Int = ColorUtils.setAlphaComponent(color, TENTATIVE_ALPHA)

    private fun dayNumberColor(cell: MonthCell): Int {
        if (!cell.inMonth) return color(R.color.widget_outside)
        // FR-4: 祝日と日曜は朱、土曜は縹。アプリの月表示と同じ配色。
        return when {
            cell.holiday != null || cell.date.dayOfWeek == DayOfWeek.SUNDAY ->
                color(R.color.widget_sunday)
            cell.date.dayOfWeek == DayOfWeek.SATURDAY -> color(R.color.widget_saturday)
            else -> color(R.color.widget_text)
        }
    }

    private fun color(resId: Int): Int = ContextCompat.getColor(context, resId)

    private fun buildCells(): List<MonthCell> {
        val payload = KanSukeWidget.readPayload(context) ?: return emptyList()
        if (payload.optInt("version") != KanSukeWidget.PAYLOAD_VERSION) return emptyList()
        if (!payload.optBoolean("signedIn", false)) return emptyList()

        val daysByDate = mutableMapOf<String, JSONObject>()
        val days = payload.optJSONArray("days") ?: JSONArray()
        for (index in 0 until days.length()) {
            val day = days.optJSONObject(index) ?: continue
            val date = day.optString("date")
            if (date.isEmpty()) continue
            daysByDate[date] = day
        }

        // 複数人の予定の地色。未設定ならテーマ既定（ライト/ダークの色リソース）。
        val mergedBarColor =
            if (payload.has("mergedBarColor")) {
                KanSukeWidget.parseColor(payload.optString("mergedBarColor"))
            } else {
                color(R.color.widget_merged_bar)
            }

        val today = LocalDate.now()
        val firstOfMonth = today.withDayOfMonth(1)
        // DayOfWeek は月=1〜日=7。日曜始まりのグリッドに合わせる。
        val leadingDays = firstOfMonth.dayOfWeek.value % COLUMNS
        val gridStart = firstOfMonth.minusDays(leadingDays.toLong())
        // 1 日が土曜で 31 日ある月だけ 6 週になる。必要な週数だけ描いてマスを高く保つ。
        val weeks = (leadingDays + today.lengthOfMonth() + COLUMNS - 1) / COLUMNS

        return (0 until weeks * COLUMNS).map { offset ->
            val date = gridStart.plusDays(offset.toLong())
            // LocalDate.toString() は ISO（yyyy-MM-dd）で、Flutter 側のキーと一致する。
            val day = daysByDate[date.toString()]
            MonthCell(
                date = date,
                inMonth = date.monthValue == today.monthValue && date.year == today.year,
                isToday = date == today,
                holiday = day?.optString("holiday")?.ifEmpty { null },
                chips = parseChips(day?.optJSONArray("entries"), mergedBarColor),
                total = day?.optInt("total") ?: 0,
            )
        }
    }

    private fun parseChips(entries: JSONArray?, mergedBarColor: Int): List<MonthChip> {
        if (entries == null) return emptyList()
        val chips = mutableListOf<MonthChip>()
        for (index in 0 until minOf(entries.length(), CHIP_IDS.size)) {
            val entry = entries.optJSONObject(index) ?: continue
            val colors = entry.optJSONArray("colors")
            // FR-2: 1 人の予定は本人の識別色、複数人はまとめ帯の地色（アプリと同じ）。
            val color =
                when {
                    colors == null || colors.length() == 0 -> KanSukeWidget.FALLBACK_COLOR
                    colors.length() == 1 -> KanSukeWidget.parseColor(colors.optString(0))
                    else -> mergedBarColor
                }
            chips +=
                MonthChip(
                    title = entry.optString("title"),
                    color = color,
                    tentative = entry.optBoolean("tentative", false),
                )
        }
        return chips
    }

    private companion object {
        const val COLUMNS = 7

        /** 仮の予定の地色の不透明度（0〜255）。地紋の上でも「薄い塗り」と分かる濃さ。 */
        const val TENTATIVE_ALPHA = 0x59

        /** 1 マスに置ける帯の本数。あふれたぶんは「+N」になる。 */
        val CHIP_IDS =
            intArrayOf(
                R.id.month_cell_chip_1,
                R.id.month_cell_chip_2,
                R.id.month_cell_chip_3,
            )
    }
}

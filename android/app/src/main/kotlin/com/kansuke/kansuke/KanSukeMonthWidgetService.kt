package com.kansuke.kansuke

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
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
        KanSukeMonthWidgetFactory(
            applicationContext,
            // マスの高さを実サイズから決めるため、どのウィジェットぶんかを覚えておく。
            intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            ),
        )
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

class KanSukeMonthWidgetFactory(
    private val context: Context,
    private val appWidgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID,
) : RemoteViewsService.RemoteViewsFactory {

    private var cells: List<MonthCell> = emptyList()

    /**
     * マス 1 つの高さ（px）。
     *
     * GridView は行の高さを引き伸ばさないので、何もしないとマスはレイアウトの
     * minHeight のまま上に詰まり、ウィジェットの下半分が余る。ウィジェットの
     * 実サイズを週数で割った高さを各マスに与えて、グリッドで埋める。
     */
    private var cellHeightPx: Int = 0

    /** 1 マスに置ける帯の本数。マスが高いほど増やして余白を使い切る。 */
    private var chipSlots: Int = DEFAULT_CHIP_SLOTS

    /** 設定「ウィジェットの外観」。マスの罫線・日付の色に効く。 */
    private var theme: WidgetTheme = WidgetTheme(context, WidgetAppearance.SYSTEM)

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        theme = KanSukeWidget.readAppearance(context)
        cells = buildCells()
        measureCells()
    }

    override fun onDestroy() {
        cells = emptyList()
    }

    override fun getCount(): Int = cells.size

    override fun getViewAt(position: Int): RemoteViews {
        val cell = cells.getOrNull(position)
        val views = RemoteViews(context.packageName, R.layout.kansuke_month_widget_cell)
        // マスは使い回されるので、リサイズ後に前の高さが残らないよう毎回入れ直す。
        views.setInt(R.id.month_cell_root, "setMinimumHeight", cellHeightPx)
        if (cell == null) return views

        views.setInt(
            R.id.month_cell_root,
            "setBackgroundResource",
            if (cell.isToday) theme.cellTodayRes else theme.cellRes,
        )

        views.setTextViewText(R.id.month_cell_day, cell.date.dayOfMonth.toString())
        views.setTextColor(R.id.month_cell_day, dayNumberColor(cell))
        // FR-4: 今日は日付を丸で囲む（アプリの月表示と同じ目印）。
        if (cell.isToday) {
            views.setInt(R.id.month_cell_day, "setBackgroundResource", theme.dayTodayRes)
            views.setTextColor(R.id.month_cell_day, theme.background)
        } else {
            views.setInt(R.id.month_cell_day, "setBackgroundResource", 0)
        }

        if (cell.holiday == null) {
            views.setViewVisibility(R.id.month_cell_holiday, View.GONE)
        } else {
            views.setViewVisibility(R.id.month_cell_holiday, View.VISIBLE)
            views.setTextViewText(R.id.month_cell_holiday, cell.holiday)
            views.setTextColor(R.id.month_cell_holiday, theme.sunday)
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
     * ウィジェットの実サイズからマスの高さ（[cellHeightPx]）と帯の本数
     * （[chipSlots]）を決める。
     *
     * 高さはランチャーが AppWidgetOptions で教えてくれる（縦向きの高さは
     * MAX_HEIGHT 側。MIN_HEIGHT は横向きぶん）。取れないときはレイアウトの
     * minHeight に任せる＝この対応を入れる前と同じ見た目になる。
     */
    private fun measureCells() {
        val density = context.resources.displayMetrics.density
        cellHeightPx = (MIN_CELL_DP * density).toInt()
        chipSlots = DEFAULT_CHIP_SLOTS

        val weeks = cells.size / COLUMNS
        if (weeks == 0 || appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val options =
            runCatching { AppWidgetManager.getInstance(context).getAppWidgetOptions(appWidgetId) }
                .getOrNull() ?: return
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (heightDp <= 0) return

        val gridPx = heightDp * density - chromeHeightPx()
        val heightPx = (gridPx / weeks).toInt()
        if (heightPx <= cellHeightPx) return
        cellHeightPx = heightPx
        chipSlots = chipSlotsFor(heightPx)
    }

    /** グリッドの外側（外枠の余白・見出しの月・曜日見出し）が使う高さ（px）。 */
    private fun chromeHeightPx(): Float {
        val density = context.resources.displayMetrics.density
        val title = textHeightPx(TITLE_TEXT_SP)
        // 見出しの行はアイコン（16dp）と月の文字の高い方で決まる。
        val header = maxOf(title, HEADER_ICON_DP * density)
        return CHROME_PADDING_DP * density + header + textHeightPx(DAY_OF_WEEK_TEXT_SP)
    }

    /** マスの高さに収まる帯の本数。日付の行を除いた残りを帯の高さで割る。 */
    private fun chipSlotsFor(heightPx: Int): Int {
        val density = context.resources.displayMetrics.density
        val chipPx = textHeightPx(CHIP_TEXT_SP) + CHIP_MARGIN_DP * density
        if (chipPx <= 0f) return DEFAULT_CHIP_SLOTS
        val dayRowPx = (CELL_PADDING_DP + CELL_DAY_DP) * density
        return ((heightPx - dayRowPx) / chipPx).toInt().coerceIn(1, CHIP_IDS.size)
    }

    /** sp 指定の 1 行が占める高さ（px）。端末の文字サイズ設定（fontScale）も見る。 */
    private fun textHeightPx(sizeSp: Float): Float {
        val resources = context.resources
        return sizeSp *
            resources.displayMetrics.density *
            resources.configuration.fontScale *
            LINE_HEIGHT_RATIO
    }

    /**
     * マスへ予定の帯を積む。
     *
     * 帯は [chipSlots] 本ぶんしか置けない。収まらない件数がある場合は、
     * **最後の 1 枠を「+N」に明け渡す**（アプリの月表示と同じで、「+N」もレーンを
     * 1 本使う）。こうするとマスの中身が [chipSlots] 本ぶんで頭打ちになり、
     * マスの高さ（[cellHeightPx]）からはみ出してグリッドがずれることがない。
     *
     * 並びは Flutter 側で日別一覧と同じ順に整列済みなので、上から順に置くだけでよい。
     */
    private fun bindChips(views: RemoteViews, cell: MonthCell) {
        val overflows = cell.total > chipSlots
        val shown =
            if (overflows) chipSlots - 1 else minOf(cell.chips.size, chipSlots)
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
                views.setTextColor(viewId, theme.text)
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
            theme.applyTextColor(views, R.id.month_cell_more, theme.textSubtle)
        } else {
            views.setViewVisibility(R.id.month_cell_more, View.GONE)
        }
    }

    /** 仮の予定の地色（識別色を薄く敷く）。文字は通常の文字色のまま読める濃さにする。 */
    private fun tentativeFill(color: Int): Int = ColorUtils.setAlphaComponent(color, TENTATIVE_ALPHA)

    private fun dayNumberColor(cell: MonthCell): Int {
        if (!cell.inMonth) return theme.outside
        // FR-4: 祝日と日曜は朱、土曜は縹。アプリの月表示と同じ配色。
        return when {
            cell.holiday != null || cell.date.dayOfWeek == DayOfWeek.SUNDAY -> theme.sunday
            cell.date.dayOfWeek == DayOfWeek.SATURDAY -> theme.saturday
            else -> theme.text
        }
    }

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

        // 複数人の予定の地色。未設定なら外観に合わせた既定（ライト/ダーク）。
        val mergedBarColor =
            if (payload.has("mergedBarColor")) {
                KanSukeWidget.parseColor(payload.optString("mergedBarColor"))
            } else {
                theme.mergedBar
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

        /** 帯の枠（上限）。実際に使う本数はマスの高さで決まる。あふれたら「+N」。 */
        val CHIP_IDS =
            intArrayOf(
                R.id.month_cell_chip_1,
                R.id.month_cell_chip_2,
                R.id.month_cell_chip_3,
                R.id.month_cell_chip_4,
                R.id.month_cell_chip_5,
                R.id.month_cell_chip_6,
            )

        /** ウィジェットの高さが分からないときの本数（レイアウトの minHeight に収まる数）。 */
        const val DEFAULT_CHIP_SLOTS = 3

        /** レイアウト（kansuke_month_widget_cell）の minHeight と揃える。 */
        const val MIN_CELL_DP = 46f

        // 高さの見積もりに使う寸法。レイアウト・スタイル側の値と対応させる。
        const val CHROME_PADDING_DP = 22f // 外枠 8dp*2 + 見出し 4dp + 曜日 2dp
        const val HEADER_ICON_DP = 16f
        const val TITLE_TEXT_SP = 14f
        const val DAY_OF_WEEK_TEXT_SP = 10f
        const val CELL_PADDING_DP = 3f // マスの上 1dp + 下 2dp
        const val CELL_DAY_DP = 14f // 日付の TextView の高さ
        const val CHIP_TEXT_SP = 8f
        const val CHIP_MARGIN_DP = 1f

        /** 1 行の TextView が文字サイズの何倍の高さを取るか（行間ぶんの余裕）。 */
        const val LINE_HEIGHT_RATIO = 1.4f
    }
}

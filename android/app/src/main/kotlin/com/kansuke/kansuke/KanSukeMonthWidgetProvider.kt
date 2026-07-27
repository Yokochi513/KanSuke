package com.kansuke.kansuke

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate

/**
 * 月表示のホーム画面ウィジェット（Issue #127、FR-4）。既定サイズは 4x5 マス。
 *
 * 表示する予定は Flutter 側（HomeWidgetSync）が `home_widget` の SharedPreferences
 * へ JSON で書き込み、マスの組み立てと描画は [KanSukeMonthWidgetService] が行う。
 * ここは外枠・見出しの月と、グリッドをサービスへ繋ぐアダプタだけを持つ。
 */
class KanSukeMonthWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // 見出しの月も描画時の日付で決める。定期更新（30 分）で月をまたいでも
        // グリッド（KanSukeMonthWidgetFactory）と食い違わない。
        val today = LocalDate.now()
        val title =
            context.getString(
                R.string.kansuke_month_widget_title,
                today.year,
                today.monthValue,
            )

        // 設定「ウィジェットの外観」（システム追従／ライト／ダーク／透過）。
        val theme = KanSukeWidget.readAppearance(context)

        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.kansuke_month_widget)
            views.setTextViewText(R.id.month_widget_title, title)
            theme.applyBackground(views, R.id.month_widget_root)
            theme.applyTextColor(views, R.id.month_widget_title, theme.text)
            theme.applyTextColor(views, R.id.month_widget_empty, theme.textSubtle)
            // 曜日見出しは日曜=朱・土曜=縹、平日は薄墨（レイアウトと同じ配色）。
            DAY_OF_WEEK_IDS.forEachIndexed { index, viewId ->
                val color =
                    when (index) {
                        0 -> theme.sunday
                        DAY_OF_WEEK_IDS.lastIndex -> theme.saturday
                        else -> theme.textSubtle
                    }
                theme.applyTextColor(views, viewId, color)
            }

            val serviceIntent =
                Intent(context, KanSukeMonthWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    // RemoteViews は Intent を URI で同一視するため、ウィジェット ID を
                    // data にも埋める（複数配置したときに Factory を共有させない）。
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
            views.setRemoteAdapter(R.id.month_widget_grid, serviceIntent)
            views.setEmptyView(R.id.month_widget_grid, R.id.month_widget_empty)

            val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.month_widget_header, launch)
            views.setPendingIntentTemplate(
                R.id.month_widget_grid,
                KanSukeWidget.launchTemplate(context),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
            // 保存済みの JSON が差し替わっているので、グリッドの読み直しを促す。
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.month_widget_grid)
        }
    }

    /**
     * リサイズされたらグリッドを組み直す。
     *
     * マスの高さはウィジェットの実サイズから決めている（KanSukeMonthWidgetFactory）ので、
     * 大きさが変わったら読み直させないと前の高さのまま残る。
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.month_widget_grid)
    }

    private companion object {
        /** 曜日見出し（日〜土）。並び順で色を決めるので順序を変えないこと。 */
        val DAY_OF_WEEK_IDS =
            intArrayOf(
                R.id.month_widget_dow_0,
                R.id.month_widget_dow_1,
                R.id.month_widget_dow_2,
                R.id.month_widget_dow_3,
                R.id.month_widget_dow_4,
                R.id.month_widget_dow_5,
                R.id.month_widget_dow_6,
            )
    }
}

package com.kansuke.kansuke

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 今日・明日の予定を並べるホーム画面ウィジェット（Issue #127、FR-4）。
 *
 * 表示する予定は Flutter 側（HomeWidgetSync）が `home_widget` の SharedPreferences
 * へ JSON で書き込み、行の組み立てと描画は [KanSukeWidgetService] が行う。ここは
 * 外枠と、一覧をサービスへ繋ぐアダプタ、タップでアプリを開く導線だけを持つ。
 *
 * 月のカレンダーとして見たい場合は [KanSukeMonthWidgetProvider]（4x5）を使う。
 */
class KanSukeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.kansuke_widget)

            val serviceIntent =
                Intent(context, KanSukeWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    // RemoteViews は Intent を URI で同一視するため、ウィジェット ID を
                    // data にも埋める。ホーム画面に 2 つ以上置いたときに、同じ
                    // RemoteViewsFactory が使い回されて片方が更新されなくなるのを防ぐ。
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
            views.setRemoteAdapter(R.id.widget_list, serviceIntent)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            views.setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            // 一覧の各行のタップもアプリ起動にする。コレクションの子は
            // PendingIntent を直接持てず、テンプレート＋fill-in intent で扱う。
            views.setPendingIntentTemplate(R.id.widget_list, KanSukeWidget.launchTemplate(context))

            appWidgetManager.updateAppWidget(appWidgetId, views)
            // 保存済みの JSON が差し替わっているので、一覧の読み直しを促す。
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
        }
    }
}

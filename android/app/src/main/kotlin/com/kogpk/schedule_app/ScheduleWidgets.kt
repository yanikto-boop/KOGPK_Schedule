package com.kogpk.schedule_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

private fun renderWidget(
    context: Context,
    layoutId: Int,
    maxRows: Int,
    hasUpdated: Boolean,
    prefs: SharedPreferences,
): RemoteViews {
    val views = RemoteViews(context.packageName, layoutId)

    val group = prefs.getString("w_group", "—") ?: "—"
    val day = prefs.getString("w_day", "") ?: ""
    val updated = prefs.getString("w_updated", "") ?: ""
    val lessonsRaw = prefs.getString("w_lessons", "") ?: ""

    views.setTextViewText(R.id.w_group, group)
    views.setTextViewText(R.id.w_day, day)
    if (hasUpdated) views.setTextViewText(R.id.w_updated, updated)

    views.removeAllViews(R.id.list_container)

    val lines = lessonsRaw.split("\n").filter { it.isNotBlank() }
    if (lines.isEmpty()) {
        views.setViewVisibility(R.id.list_container, android.view.View.GONE)
        views.setViewVisibility(R.id.w_empty, android.view.View.VISIBLE)
    } else {
        views.setViewVisibility(R.id.list_container, android.view.View.VISIBLE)
        views.setViewVisibility(R.id.w_empty, android.view.View.GONE)
        val shown = lines.take(maxRows)
        for (line in shown) {
            val parts = line.split("|")
            val num = parts.getOrNull(0) ?: ""
            val time = parts.getOrNull(1) ?: ""
            val subject = parts.getOrNull(2) ?: ""
            val row = RemoteViews(context.packageName, R.layout.widget_row)
            row.setTextViewText(R.id.row_num, num)
            row.setTextViewText(R.id.row_time, time)
            row.setTextViewText(R.id.row_subject, subject)
            views.addView(R.id.list_container, row)
        }
        if (lines.size > maxRows) {
            val more = RemoteViews(context.packageName, R.layout.widget_row)
            more.setTextViewText(R.id.row_num, "")
            more.setTextViewText(R.id.row_time, "")
            more.setTextViewText(R.id.row_subject, "ещё +${lines.size - maxRows}")
            views.addView(R.id.list_container, more)
        }
    }

    // тап по виджету открывает приложение
    val intent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
        context, MainActivity::class.java
    )
    views.setOnClickPendingIntent(R.id.widget_root, intent)

    return views
}

/** Виджет 2×2 — компактный список пар. */
class ScheduleWidgetSmall : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = renderWidget(
                context, R.layout.widget_small, maxRows = 4,
                hasUpdated = false, prefs = widgetData
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** Виджет 4×2 — расширенный список пар. */
class ScheduleWidgetWide : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = renderWidget(
                context, R.layout.widget_wide, maxRows = 7,
                hasUpdated = true, prefs = widgetData
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

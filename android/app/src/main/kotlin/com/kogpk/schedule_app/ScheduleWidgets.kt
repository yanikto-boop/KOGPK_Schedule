package com.kogpk.schedule_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private val ISO = SimpleDateFormat("yyyy-MM-dd", Locale.US)

private fun todayIso(): String = ISO.format(Date())

/** Дата+время конца дня как Date (для сравнения «прошёл ли учебный день»). */
private fun endDateTime(date: String, end: String): Date? {
    return try {
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
        fmt.parse("$date ${if (end.isBlank()) "23:59" else end}")
    } catch (e: Exception) {
        null
    }
}

/** Метка дня: «Сегодня» / «Завтра» / «Понедельник, 15 июня». */
private fun dayLabel(date: String, dm: String, wd: String): String {
    val today = todayIso()
    val cal = Calendar.getInstance()
    cal.add(Calendar.DAY_OF_YEAR, 1)
    val tomorrow = ISO.format(cal.time)
    return when (date) {
        today -> "Сегодня"
        tomorrow -> "Завтра"
        else -> if (wd.isNotBlank())
            wd.replaceFirstChar { it.uppercase() } + ", " + dm
        else dm
    }
}

/** Выбирает день для показа: первый, чей конец ещё не наступил. */
private fun pickDay(days: JSONArray): JSONObject? {
    val now = Date()
    for (i in 0 until days.length()) {
        val d = days.getJSONObject(i)
        val end = endDateTime(d.optString("date"), d.optString("end"))
        if (end != null && end.after(now)) return d
    }
    // всё прошло — показываем последний доступный (или ничего)
    return if (days.length() > 0) days.getJSONObject(days.length() - 1) else null
}

private fun renderWidget(
    context: Context,
    layoutId: Int,
    maxRows: Int,
    hasUpdated: Boolean,
    prefs: SharedPreferences,
): RemoteViews {
    val views = RemoteViews(context.packageName, layoutId)

    val group = prefs.getString("w_group", "—") ?: "—"
    views.setTextViewText(R.id.w_group, group)
    if (hasUpdated) {
        val t = SimpleDateFormat("HH:mm", Locale.US).format(Date())
        views.setTextViewText(R.id.w_updated, t)
    }

    val day: JSONObject? = try {
        val raw = prefs.getString("w_days", "[]") ?: "[]"
        pickDay(JSONArray(raw))
    } catch (e: Exception) {
        null
    }

    views.removeAllViews(R.id.list_container)

    val lessons: JSONArray? = day?.optJSONArray("lessons")
    if (day == null || lessons == null || lessons.length() == 0) {
        views.setTextViewText(R.id.w_day, "")
        views.setViewVisibility(R.id.list_container, android.view.View.GONE)
        views.setViewVisibility(R.id.w_empty, android.view.View.VISIBLE)
    } else {
        views.setTextViewText(
            R.id.w_day,
            dayLabel(day.optString("date"), day.optString("dm"), day.optString("wd"))
        )
        views.setViewVisibility(R.id.list_container, android.view.View.VISIBLE)
        views.setViewVisibility(R.id.w_empty, android.view.View.GONE)

        val total = lessons.length()
        val shown = minOf(total, maxRows)
        for (i in 0 until shown) {
            val parts = lessons.getString(i).split("|")
            val row = RemoteViews(context.packageName, R.layout.widget_row)
            row.setTextViewText(R.id.row_num, parts.getOrNull(0) ?: "")
            row.setTextViewText(R.id.row_time, parts.getOrNull(1) ?: "")
            row.setTextViewText(R.id.row_subject, parts.getOrNull(2) ?: "")
            views.addView(R.id.list_container, row)
        }
        if (total > maxRows) {
            val more = RemoteViews(context.packageName, R.layout.widget_row)
            more.setTextViewText(R.id.row_num, "")
            more.setTextViewText(R.id.row_time, "")
            more.setTextViewText(R.id.row_subject, "ещё +${total - maxRows}")
            views.addView(R.id.list_container, more)
        }
    }

    // тап по виджету открывает приложение
    val launch = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val pi = PendingIntent.getActivity(
        context, 0, launch,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.widget_root, pi)

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

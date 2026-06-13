package com.kogpk.schedule_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Виджет «Прибытие автобуса» — сам тянет живые данные с нашего API. */
class BusWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val sid = widgetData.getInt("bus_widget_sid", -1)
        val name = widgetData.getString("bus_widget_name", null)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_bus)
            views.setTextViewText(R.id.bus_stop, name ?: "Остановка не выбрана")

            // тап по виджету — открыть приложение
            val openPi = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.bus_root, openPi)

            // кнопка обновить — перезапуск onUpdate этого виджета
            val refreshIntent = Intent(context, BusWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS,
                    appWidgetManager.getAppWidgetIds(
                        ComponentName(context, BusWidget::class.java)))
            }
            val refreshPi = PendingIntent.getBroadcast(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.bus_refresh, refreshPi)

            if (sid <= 0) {
                views.setViewVisibility(R.id.bus_list, android.view.View.GONE)
                views.setViewVisibility(R.id.bus_empty, android.view.View.VISIBLE)
                views.setTextViewText(R.id.bus_empty,
                    "Добавьте остановку в избранное в приложении")
                appWidgetManager.updateAppWidget(id, views)
                continue
            }

            appWidgetManager.updateAppWidget(id, views) // мгновенный каркас
            fetchAndRender(context, appWidgetManager, id, sid, name)
        }
    }

    private fun fetchAndRender(
        context: Context, mgr: AppWidgetManager, id: Int, sid: Int, name: String?,
    ) {
        Thread {
            val items = try {
                val url = URL("https://vpn-ornux.space/sapi/bus/forecast?sid=$sid")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000; readTimeout = 8000
                    setRequestProperty("User-Agent", "KOGPKScheduleWidget")
                }
                val body = conn.inputStream.bufferedReader().readText()
                conn.disconnect()
                val obj = org.json.JSONObject(body)
                obj.optJSONArray("forecasts") ?: JSONArray()
            } catch (e: Exception) {
                null
            }

            val views = RemoteViews(context.packageName, R.layout.widget_bus)
            views.setTextViewText(R.id.bus_stop, name ?: "Остановка")

            val openPi = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.bus_root, openPi)
            val refreshIntent = Intent(context, BusWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(id))
            }
            val refreshPi = PendingIntent.getBroadcast(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.bus_refresh, refreshPi)

            views.removeAllViews(R.id.bus_list)
            val n = items?.length() ?: 0
            if (items == null) {
                views.setViewVisibility(R.id.bus_list, android.view.View.GONE)
                views.setViewVisibility(R.id.bus_empty, android.view.View.VISIBLE)
                views.setTextViewText(R.id.bus_empty, "Нет связи, нажмите ⟳")
            } else if (n == 0) {
                views.setViewVisibility(R.id.bus_list, android.view.View.GONE)
                views.setViewVisibility(R.id.bus_empty, android.view.View.VISIBLE)
                views.setTextViewText(R.id.bus_empty, "Сейчас автобусов нет")
            } else {
                views.setViewVisibility(R.id.bus_list, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.bus_empty, android.view.View.GONE)
                val max = minOf(n, 5)
                for (i in 0 until max) {
                    val f = items.getJSONObject(i)
                    val row = RemoteViews(context.packageName, R.layout.widget_bus_row)
                    row.setTextViewText(R.id.brow_num, f.optString("route_num"))
                    val t = if (f.optBoolean("arriving")) "подъезжает"
                            else "${f.optInt("minutes")} мин"
                    row.setTextViewText(R.id.brow_time, t)
                    views.addView(R.id.bus_list, row)
                }
            }
            mgr.updateAppWidget(id, views)
        }.start()
    }
}

package com.kogpk.schedule_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Виджеты-таймеры «до конца половины / до конца перерыва / до начала пар».
 *
 * Стадии заранее считает приложение (CountdownTimeline в Dart) и кладёт
 * в `w_timeline`. Здесь только находим стадию на текущий момент, отдаём
 * отсчёт лаунчеру через Chronometer (он тикает сам, без нашего кода) и
 * ставим будильник на конец стадии, чтобы перерисоваться к следующей.
 */
object Countdown {
    private const val KEY = "w_timeline"
    private const val TICK_REQUEST = 4201

    private class Phase(
        val from: Long, val to: Long,
        val label: String, val title: String, val sub: String,
        val timer: Boolean,
    )

    private fun phases(prefs: SharedPreferences): List<Phase> = try {
        val arr = JSONArray(prefs.getString(KEY, "[]") ?: "[]")
        (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            Phase(
                o.getLong("f"), o.getLong("t"),
                o.optString("lb"), o.optString("tl"), o.optString("sb"),
                o.optBoolean("tm"),
            )
        }
    } catch (e: Exception) {
        emptyList()
    }

    private val providers = listOf(
        CountdownWidgetSmall::class.java to R.layout.widget_countdown_small,
        CountdownWidgetMedium::class.java to R.layout.widget_countdown_medium,
    )

    /** Перерисовать все таймеры и перепоставить будильник. */
    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val prefs = HomeWidgetPlugin.getData(context)
        val all = phases(prefs)
        val now = System.currentTimeMillis()
        var placed = 0
        for ((cls, layout) in providers) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            placed += ids.size
            for (id in ids) mgr.updateAppWidget(id, render(context, layout, all, now))
        }
        if (placed > 0) scheduleNext(context, all, now) else cancel(context)
    }

    private fun render(
        context: Context, layout: Int, all: List<Phase>, now: Long,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        val p = all.firstOrNull { now >= it.from && now < it.to }

        when {
            p == null -> {
                v.setTextViewText(R.id.cd_label, "Расписание")
                showStatic(v, if (all.isEmpty()) "Открой приложение" else "Пар больше нет")
                v.setTextViewText(R.id.cd_title, "")
                v.setTextViewText(R.id.cd_sub, "Данные обновятся при запуске")
            }
            p.timer -> {
                v.setTextViewText(R.id.cd_label, p.label)
                v.setViewVisibility(R.id.cd_timer, View.VISIBLE)
                v.setViewVisibility(R.id.cd_static, View.GONE)
                // база в шкале elapsedRealtime: Chronometer в режиме обратного
                // отсчёта показывает (base - elapsedRealtime)
                val base = SystemClock.elapsedRealtime() + (p.to - now)
                v.setChronometerCountDown(R.id.cd_timer, true)
                v.setChronometer(R.id.cd_timer, base, null, true)
                v.setTextViewText(R.id.cd_title, p.title)
                v.setTextViewText(R.id.cd_sub, p.sub)
            }
            else -> {
                v.setTextViewText(R.id.cd_label, p.label)
                showStatic(v, p.sub)
                v.setTextViewText(R.id.cd_title, p.title)
                v.setTextViewText(R.id.cd_sub, "")
            }
        }

        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        v.setOnClickPendingIntent(
            R.id.cd_root,
            PendingIntent.getActivity(
                context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )
        return v
    }

    private fun showStatic(v: RemoteViews, text: String) {
        v.setChronometer(R.id.cd_timer, SystemClock.elapsedRealtime(), null, false)
        v.setViewVisibility(R.id.cd_timer, View.GONE)
        v.setViewVisibility(R.id.cd_static, View.VISIBLE)
        v.setTextViewText(R.id.cd_static, text)
    }

    private fun tickIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, TICK_REQUEST,
        Intent(context, CountdownTickReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    fun canExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    /** Будильник на ближайшую смену стадии. */
    private fun scheduleNext(context: Context, all: List<Phase>, now: Long) {
        val next = all.asSequence()
            .flatMap { sequenceOf(it.from, it.to) }
            .filter { it > now }
            .minOrNull()
        if (next == null) {
            cancel(context)
            return
        }
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val at = next + 1000 // на секунду позже звонка — уже внутри новой стадии
        // RTC без WAKEUP: при выключенном экране будить телефон незачем,
        // будильник сработает, как только экран включат.
        if (canExact(context)) {
            am.setExact(AlarmManager.RTC, at, tickIntent(context))
        } else {
            am.set(AlarmManager.RTC, at, tickIntent(context))
        }
    }

    private fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(tickIntent(context))
    }
}

/** Будильник смены стадии, а также перезагрузка, смена времени и выдача
 *  разрешения на точные будильники — во всех случаях просто перерисовка. */
class CountdownTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Countdown.updateAll(context)
    }
}

/** Таймер 2×1: стадия и отсчёт. */
class CountdownWidgetSmall : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray, widgetData: SharedPreferences,
    ) = Countdown.updateAll(context)

    override fun onDisabled(context: Context) = Countdown.updateAll(context)
}

/** Таймер 2×2: стадия, отсчёт и текущая/следующая пара. */
class CountdownWidgetMedium : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray, widgetData: SharedPreferences,
    ) = Countdown.updateAll(context)

    override fun onDisabled(context: Context) = Countdown.updateAll(context)
}

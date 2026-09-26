package com.kogpk.schedule_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "com.kogpk.schedule/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "path is null", null)
                        } else {
                            installApk(path)
                            result.success(true)
                        }
                    }
                    "pinWidget" -> {
                        val which = call.argument<String>("which") ?: "small"
                        result.success(pinWidget(which))
                    }
                    "canPinWidget" -> result.success(canPinWidget())
                    "exactAlarmAllowed" -> result.success(Countdown.canExact(this))
                    "requestExactAlarm" -> result.success(requestExactAlarm())
                    "countdownWidgetsPlaced" -> result.success(countdownWidgetsPlaced())
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String) {
        val file = File(path)
        val uri: Uri = FileProvider.getUriForFile(
            this, "$packageName.fileprovider", file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        startActivity(intent)
    }

    private fun canPinWidget(): Boolean {
        val mgr = getSystemService(AppWidgetManager::class.java)
        return mgr != null && mgr.isRequestPinAppWidgetSupported
    }

    private fun pinWidget(which: String): Boolean {
        val mgr = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!mgr.isRequestPinAppWidgetSupported) return false
        val cls = when (which) {
            "wide" -> ScheduleWidgetWide::class.java
            "bus" -> BusWidget::class.java
            "countdown_small" -> CountdownWidgetSmall::class.java
            "countdown_medium" -> CountdownWidgetMedium::class.java
            else -> ScheduleWidgetSmall::class.java
        }
        val provider = ComponentName(this, cls)
        return mgr.requestPinAppWidget(provider, null, null)
    }

    /** Открывает системный экран «Будильники и напоминания» для приложения. */
    private fun requestExactAlarm(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName"))
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun countdownWidgetsPlaced(): Boolean {
        val mgr = AppWidgetManager.getInstance(this)
        return listOf(CountdownWidgetSmall::class.java, CountdownWidgetMedium::class.java)
            .any { mgr.getAppWidgetIds(ComponentName(this, it)).isNotEmpty() }
    }
}

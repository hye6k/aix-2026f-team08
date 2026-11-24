package io.github.hye6k.morning_routine

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.text.format.DateFormat
import org.json.JSONObject
import java.util.Calendar
import java.util.Date

internal class DepartureReminder(
    private val context: Context,
    private val isTest: Boolean = false,
) {
    private val prefs = context.getSharedPreferences(if (isTest) "departure_reminder_test" else "departure_reminder", Context.MODE_PRIVATE)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    private val reminderId = if (isTest) TEST_ID else ID

    private data class Occurrence(val day: String, val at: Long, val destination: String)

    fun configure(config: String) {
        if (prefs.getString("config", null) == config) {
            if (!prefs.contains("next")) refresh()
            return
        }
        prefs.edit().putString("config", config).apply()
        val settings = JSONObject(config)
        val posted = prefs.getString("postedDay", null)
        if (!settings.optBoolean("enabled") ||
            posted != null && settings.optJSONArray("departed")?.let { days ->
                (0 until days.length()).any { days.getString(it) == posted }
            } == true
        ) notifications.cancel(reminderId)
        refresh()
    }

    private fun operation(action: String, id: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context, id, Intent(context, DepartureReminderReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun schedule(type: Int, at: Long, pending: PendingIntent): Boolean {
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
            try {
                alarms.setExactAndAllowWhileIdle(type, at, pending)
                return true
            } catch (_: SecurityException) {
                // Exact alarm access can change before registration.
            }
        }
        alarms.setAndAllowWhileIdle(type, at, pending)
        return false
    }

    fun refresh(deliver: Boolean = false) {
        val pending = operation(if (isTest) TEST_TICK else TICK, reminderId)
        alarms.cancel(pending)
        val scheduled = prefs.getLong("next", 0)
        prefs.edit().remove("next").apply()
        val config = JSONObject(prefs.getString("config", "{}") ?: "{}")
        if (!config.optBoolean("enabled")) return
        val routes = config.optJSONArray("routes")
        val departed = config.optJSONArray("departed")
        val posted = prefs.getString("postedDay", null)
        val now = System.currentTimeMillis()
        var next: Occurrence? = null
        fun consider(occurrence: Occurrence) {
            val at = occurrence.at
            if (deliver && at == scheduled && now >= at && now - at <= 5 * 60_000L) {
                if (post(occurrence.destination, at, reminderId)) {
                    prefs.edit().putString("postedDay", occurrence.day).apply()
                }
            } else if (at > now && (next?.at ?: Long.MAX_VALUE) > at) {
                next = occurrence
            }
        }
        if (isTest) {
            val at = config.optLong("testAt")
            consider(Occurrence(at.toString(), at, "학교"))
        }
        for (offset in if (routes == null) IntRange.EMPTY else 0..8) {
            val day = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, offset) }
            val dayKey = "${day.get(Calendar.YEAR)}-${day.get(Calendar.MONTH) + 1}-${day.get(Calendar.DAY_OF_MONTH)}"
            if (dayKey == posted || departed?.let { days ->
                    (0 until days.length()).any { days.getString(it) == dayKey }
                } == true) continue
            val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            for (index in 0 until (routes?.length() ?: 0)) {
                val route = routes!!.getJSONObject(index)
                val days = route.getJSONArray("days")
                if ((0 until days.length()).none { days.getInt(it) == weekday }) continue
                val deadline = (day.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, route.getInt("hour"))
                    set(Calendar.MINUTE, route.getInt("minute"))
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                val at = deadline - route.getInt("travelMinutes") * 60_000L
                consider(Occurrence(dayKey, at, route.getString("destination")))
            }
        }
        next?.let {
            schedule(AlarmManager.RTC_WAKEUP, it.at, pending)
            prefs.edit().putLong("next", it.at).apply()
        }
    }

    private fun canNotify(): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            notifications.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 ||
                notifications.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)

    fun scheduleVerification(): String {
        if (!canNotify()) return "blocked"
        configure(JSONObject().put("enabled", true)
            .put("testAt", System.currentTimeMillis() + 10_000).toString())
        return if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
            "scheduled" else "scheduled_inexact"
    }

    fun cancelVerification() {
        configure(JSONObject().put("enabled", false).toString())
    }

    fun preview(): String {
        if (!canNotify()) return "blocked"
        val exact = schedule(
            AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + 10_000,
            operation(PREVIEW, PREVIEW_ID)
        )
        return if (exact) "scheduled" else "scheduled_inexact"
    }

    fun showPreview() {
        post("학교", System.currentTimeMillis(), PREVIEW_ID)
    }

    private fun post(destination: String, at: Long, id: Int): Boolean {
        if (!canNotify()) return false
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "출발 안내", NotificationManager.IMPORTANCE_HIGH)
            )
            Notification.Builder(context, CHANNEL).setTimeoutAfter(15 * 60_000L)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND)
        }
        val open = PendingIntent.getActivity(
            context, id,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("open_routine_summary", true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val time = DateFormat.getTimeFormat(context).format(Date(at))
        notifications.notify(id, builder
            .setSmallIcon(R.drawable.ic_routine_sunrise)
            .setContentTitle(if (id == PREVIEW_ID || isTest) "출발 안내 테스트" else "출발할 시간이에요")
            .setContentText("$destination · 권장 출발 $time")
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build())
        return true
    }

    companion object {
        const val TICK = "io.github.hye6k.morning_routine.DEPARTURE_TICK"
        const val TEST_TICK = "io.github.hye6k.morning_routine.DEPARTURE_TEST_TICK"
        const val PREVIEW = "io.github.hye6k.morning_routine.DEPARTURE_PREVIEW"
        private const val ID = 4830
        private const val TEST_ID = 4832
        private const val PREVIEW_ID = 4831
        private const val CHANNEL = "departure_reminder"
    }
}

class DepartureReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminder = DepartureReminder(context)
        when (intent.action) {
            DepartureReminder.PREVIEW -> reminder.showPreview()
            DepartureReminder.TEST_TICK -> DepartureReminder(context, isTest = true).refresh(deliver = true)
            DepartureReminder.TICK -> reminder.refresh(deliver = true)
            else -> reminder.refresh()
        }
    }
}

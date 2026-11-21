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
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

internal class BedtimeReminders(private val context: Context) {
    private val prefs = context.getSharedPreferences("bedtime_reminders", Context.MODE_PRIVATE)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    private data class Reminder(val at: Long, val wakeAt: Long, val name: String)

    fun configure(config: String) {
        val changed = prefs.getString("config", null) != config
        if (changed) {
            prefs.edit().putString("config", config).apply()
        }
        refresh(scheduleChanged = changed)
    }

    private fun operation(action: String, id: Int, wakeAt: Long = 0): PendingIntent =
        PendingIntent.getBroadcast(
            context, id,
            Intent(context, BedtimeReminderReceiver::class.java).setAction(action)
                .putExtra("wakeAt", wakeAt),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun confirm(wakeAt: Long) {
        if (prefs.getLong("active", 0) != wakeAt) return
        prefs.edit().putLong("confirmed", wakeAt).remove("active").apply()
        notifications.cancel(CARD)
        refresh()
    }

    fun refresh(scheduleChanged: Boolean = false) {
        val alarm = operation(TICK, CARD)
        alarms.cancel(alarm)
        val config = JSONObject(prefs.getString("config", "{}") ?: "{}")
        val routes = config.optJSONArray("routes") ?: JSONArray()
        if (!config.optBoolean("enabled") || routes.length() == 0) {
            notifications.cancel(CARD)
            prefs.edit().remove("active").remove("postedAt").apply()
            return
        }

        val now = System.currentTimeMillis()
        val goal = config.getLong("goalMinutes") * MINUTE
        val lead = config.getLong("leadMinutes") * MINUTE
        val confirmed = prefs.getLong("confirmed", 0)
        val reminders = mutableListOf<Reminder>()
        for (offset in -1..8) {
            val day = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, offset) }
            val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            for (i in 0 until routes.length()) {
                val route = routes.getJSONObject(i)
                val days = route.getJSONArray("days")
                if ((0 until days.length()).none { days.getInt(it) == weekday }) continue
                val wakeAt = (day.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, route.getInt("hour"))
                    set(Calendar.MINUTE, route.getInt("minute"))
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                if (wakeAt <= confirmed) continue
                val bedtime = wakeAt - goal
                var at = bedtime - lead
                while (at < bedtime) {
                    reminders.add(Reminder(at, wakeAt, route.getString("name")))
                    at += 30 * MINUTE
                }
                reminders.add(Reminder(bedtime, wakeAt, route.getString("name")))
            }
        }
        val active = prefs.getLong("active", 0)
        val current = reminders.lastOrNull { it.wakeAt == active && it.at <= now }
        // Keep an active card until confirmation. If its schedule changed,
        // remove the stale card and use the replacement schedule.
        if (scheduleChanged && active != 0L && reminders.none { it.wakeAt == active }) {
            notifications.cancel(CARD)
            prefs.edit().remove("active").remove("postedAt").apply()
        }
        val due = current ?: if (prefs.getLong("active", 0) == 0L) {
            reminders.filter { it.at <= now && it.wakeAt > now }.maxByOrNull { it.at }
        } else null
        if (due != null && (prefs.getLong("active", 0) != due.wakeAt ||
                prefs.getLong("postedAt", 0) != due.at ||
                notifications.activeNotifications.none { it.id == CARD })
        ) {
            if (show(due, now)) {
                prefs.edit().putLong("active", due.wakeAt).putLong("postedAt", due.at).apply()
            }
        }

        val next = reminders.filter { it.at > now }.minOfOrNull { it.at } ?: return
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
            try {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm)
                return
            } catch (_: SecurityException) {
                // Exact permission may change between the check and scheduling.
            }
        }
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm)
    }

    private fun show(reminder: Reminder, now: Long): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        if (!notifications.areNotificationsEnabled()) return false
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "취침 안내", NotificationManager.IMPORTANCE_HIGH)
            )
            if (notifications.getNotificationChannel(CHANNEL).importance == NotificationManager.IMPORTANCE_NONE) return false
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND)
        }
        val wake = android.text.format.DateFormat.getTimeFormat(context)
            .format(java.util.Date(reminder.wakeAt))
        val body = if (now < reminder.wakeAt) {
            "$wake 기상 예정 · 일어나면 기상을 확인해 주세요."
        } else {
            "$wake 기상 예정이었어요 · 일어났다면 기상을 확인해 주세요."
        }
        val open = PendingIntent.getActivity(
            context, CARD,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("open_routine_summary", true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        notifications.notify(
            CARD,
            builder.setSmallIcon(R.drawable.ic_routine_notification)
                .setContentTitle(reminder.name + " · 취침 안내")
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setShowWhen(false)
                .setContentIntent(open)
                .addAction(Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(context, android.R.drawable.ic_menu_today),
                    "기상 확인",
                    operation(CONFIRM, CARD + 1, reminder.wakeAt)
                ).build())
                .build()
        )
        return true
    }

    companion object {
        const val TICK = "io.github.hye6k.morning_routine.BEDTIME_TICK"
        const val CONFIRM = "io.github.hye6k.morning_routine.BEDTIME_CONFIRM"
        private const val CARD = 4823
        private const val CHANNEL = "bedtime_reminder"
        private const val MINUTE = 60_000L
    }
}

class BedtimeReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminders = BedtimeReminders(context)
        if (intent.action == BedtimeReminders.CONFIRM) {
            reminders.confirm(intent.getLongExtra("wakeAt", 0))
        } else {
            reminders.refresh()
        }
    }
}

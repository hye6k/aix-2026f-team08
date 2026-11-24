package io.github.hye6k.morning_routine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.Calendar

internal class RoutineWakeAlarm(private val context: Context) {
    private val prefs = context.getSharedPreferences("routine_wake_alarm", Context.MODE_PRIVATE)
    private val alarms = MorningAlarms(context)

    fun configure(config: String): String {
        prefs.edit().putString("config", config).apply()
        return refresh()
    }

    fun refresh(force: Boolean = false): String {
        val config = JSONObject(prefs.getString("config", "{}") ?: "{}")
        val routes = config.optJSONArray("routes")
        if (!config.optBoolean("enabled") || routes == null || routes.length() == 0) {
            alarms.cancel(ID)
            return "off"
        }
        val permissions = alarms.permissionState()
        if (permissions["exactAlarm"] != true) return "exact_required"
        if (permissions["notifications"] != true) return "permission_required"
        val now = System.currentTimeMillis()
        val existing = alarms.currentSlot(ID)
        if (existing?.state == "ringing" && !force) return "scheduled"
        val next = (0..7).firstNotNullOfOrNull { offset ->
            val day = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, offset) }
            val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            (0 until routes.length()).firstNotNullOfOrNull { index ->
                val route = routes.getJSONObject(index)
                val days = route.getJSONArray("days")
                if ((0 until days.length()).none { days.getInt(it) == weekday }) {
                    null
                } else {
                    (day.clone() as Calendar).apply {
                        set(Calendar.HOUR_OF_DAY, route.getInt("hour"))
                        set(Calendar.MINUTE, route.getInt("minute"))
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }.timeInMillis.takeIf { it > now }
                }
            }
        } ?: return "off"
        if (force && existing != null) alarms.cancel(ID)
        if (force || existing?.atMillis != next) alarms.schedule(ID, next)
        return "scheduled"
    }

    companion object {
        const val ID = "ux-routine-wake"
        const val PREVIEW_ID = "ux-routine-wake-preview"
        fun owns(id: String) = id == ID || id == PREVIEW_ID
    }
}

class RoutineWakeRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RoutineWakeAlarm(context).refresh(force = true)
    }
}

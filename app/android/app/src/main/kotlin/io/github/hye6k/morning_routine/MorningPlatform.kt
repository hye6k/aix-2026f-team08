package io.github.hye6k.morning_routine

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal object MorningEvents {
    var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    fun pending(context: Context): JSONArray = JSONArray(context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).getString("events", "[]"))
    fun emit(context: Context, kind: String, id: String? = null, scheduledAt: Long? = null, error: String? = null) {
        val event = JSONObject().put("eventId", UUID.randomUUID().toString()).put("kind", kind).put("atMillis", System.currentTimeMillis())
        if (id != null) event.put("alarmId", id)
        if (scheduledAt != null) event.put("scheduledAtMillis", scheduledAt)
        if (error != null) event.put("error", error)
        if (kind != "screenOn") {
            val records = pending(context).put(event)
            check(context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).edit().putString("events", records.toString()).commit()) { "알람 이벤트 저장 실패" }
        }
        handler.post { sink?.success(asMap(event)) }
    }
    fun acknowledge(context: Context, eventId: String) {
        val old = pending(context)
        val remaining = JSONArray()
        for (i in 0 until old.length()) if (old.getJSONObject(i).getString("eventId") != eventId) remaining.put(old.getJSONObject(i))
        check(context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).edit().putString("events", remaining.toString()).commit())
    }
    fun asMap(value: JSONObject): Map<String, Any> = value.keys().asSequence().associateWith { value.get(it) }
}

internal class MorningAlarms(private val context: Context) {
    private val manager get() = context.getSystemService(AlarmManager::class.java)
    private val notifications get() = context.getSystemService(NotificationManager::class.java)
    private val prefs get() = context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE)
    private val channel = "morning_wake_alarm_v1"
    fun permissionState(): Map<String, Boolean> {
        createChannel()
        val exact = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
        val notification = (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && notifications.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || notifications.getNotificationChannel(channel).importance != NotificationManager.IMPORTANCE_NONE)
        return mapOf("exactAlarm" to exact, "notifications" to notification)
    }
    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(NotificationChannel(channel, "기상 알람", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 500, 1000)
        })
    }
    private fun token(id: String, action: String, at: Long = 0): PendingIntent {
        val intent = Intent(context, MorningAlarmReceiver::class.java).setAction(action)
            .setData(Uri.Builder().scheme("morning-routine").authority(action).appendPath(id).build())
            .putExtra("alarmId", id).putExtra("atMillis", at)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun state(): JSONObject = JSONObject(prefs.getString("alarms", "{}"))
    private fun save(state: JSONObject) { check(prefs.edit().putString("alarms", state.toString()).commit()) { "알람 상태 저장 실패" } }
    fun schedule(id: String, at: Long) {
        require(id.isNotBlank() && id.length <= 128) { "유효한 알람 ID가 필요합니다." }
        require(at > System.currentTimeMillis()) { "알람은 미래 시각이어야 합니다." }
        if (permissionState().values.any { !it }) throw SecurityException("알림·정확한 알람 권한을 확인하세요.")
        cancel(id)
        val show = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).setData(Uri.Builder().scheme("morning-routine").authority("open").appendPath(id).build()), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), token(id, "fire", at))
        try { save(state().put(id, JSONObject().put("atMillis", at).put("state", "scheduled"))) }
        catch (error: Exception) { manager.cancel(token(id, "fire")); throw error }
    }
    fun cancel(id: String) {
        require(id.isNotBlank())
        manager.cancel(token(id, "fire"))
        notifications.cancel(id, 0)
        val values = state(); values.remove(id); save(values)
    }
    fun isRinging(id: String, at: Long): Boolean {
        val value = state().optJSONObject(id) ?: return false
        return value.optLong("atMillis") == at && value.optString("state") == "ringing"
    }
    fun fire(id: String, at: Long) {
        val values = state()
        val record = values.optJSONObject(id) ?: return
        if (record.optLong("atMillis") != at || record.optString("state") != "scheduled") return
        record.put("state", "ringing"); save(values)
        MorningEvents.emit(context, "alarmFired", id, at)
        if (!permissionState().getValue("notifications")) {
            MorningEvents.emit(context, "alarmError", id, error = "notification_permission_denied")
            return
        }
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).setData(Uri.Builder().scheme("morning-routine").authority("open").appendPath(id).build()), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("기상 알람")
            .setContentText("기상 확인은 앱에서 별도로 진행해 주세요.").setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "알람 해제", token(id, "dismiss", at)).build())
            .addAction(Notification.Action.Builder(null, "5분 뒤 다시 울림", token(id, "snooze", at)).build())
        if (Build.VERSION.SDK_INT < 26) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_MAX).setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)).setVibrate(longArrayOf(0, 1000, 500, 1000))
        }
        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        notifications.notify(id, 0, notification)
    }
}

class MorningAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("alarmId") ?: return
        if (id.isBlank()) return
        val alarms = MorningAlarms(context)
        try {
            if (intent.action != "fire" && !alarms.isRinging(id, intent.getLongExtra("atMillis", 0))) return
            when (intent.action) {
                "fire" -> alarms.fire(id, intent.getLongExtra("atMillis", 0))
                "dismiss" -> { alarms.cancel(id); MorningEvents.emit(context, "alarmDismissed", id) }
                "snooze" -> {
                    alarms.cancel(id)
                    val at = System.currentTimeMillis() + 5 * 60_000L
                    alarms.schedule(id, at)
                    MorningEvents.emit(context, "alarmSnoozed", id, at)
                }
            }
        } catch (error: Exception) { MorningEvents.emit(context, "alarmError", id, error = error.javaClass.simpleName) }
    }
}

internal class MorningPlatform(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val context = activity.applicationContext
    private val methods = MethodChannel(messenger, "morning_routine/platform")
    private val events = EventChannel(messenger, "morning_routine/platform_events")
    private val alarms = MorningAlarms(context)
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { if (intent.action == Intent.ACTION_SCREEN_ON) MorningEvents.emit(context, "screenOn") }
    }
    init {
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED) else context.registerReceiver(receiver, filter)
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { MorningEvents.sink = sink }
    override fun onCancel(arguments: Any?) { MorningEvents.sink = null }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getPermissions" -> result.success(alarms.permissionState())
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= 31) activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}")))
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 208)
                    result.success(null)
                }
                "schedule" -> { alarms.schedule(requireNotNull(call.argument<String>("id")), requireNotNull(call.argument<Number>("atMillis")).toLong()); result.success(null) }
                "cancel" -> { alarms.cancel(requireNotNull(call.argument<String>("id"))); result.success(null) }
                "pendingAlarmEvents" -> { val values = MorningEvents.pending(context); result.success((0 until values.length()).map { MorningEvents.asMap(values.getJSONObject(it)) }) }
                "acknowledgeAlarmEvent" -> { MorningEvents.acknowledge(context, requireNotNull(call.argument<String>("eventId"))); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: IllegalArgumentException) { result.error("invalid_argument", error.message, null) }
        catch (error: SecurityException) { result.error("permission_denied", error.message, null) }
        catch (error: Exception) { result.error("platform_error", error.message, null) }
    }
    fun close() { methods.setMethodCallHandler(null); events.setStreamHandler(null); MorningEvents.sink = null; context.unregisterReceiver(receiver) }
}

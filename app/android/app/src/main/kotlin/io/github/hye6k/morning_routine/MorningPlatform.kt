package io.github.hye6k.morning_routine

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
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
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
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
    var issueListener: (() -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    fun pending(context: Context): JSONArray = JSONArray(context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).getString("events", "[]"))
    fun emit(context: Context, kind: String, id: String? = null, scheduledAt: Long? = null, error: String? = null) {
        val event = JSONObject().put("eventId", UUID.randomUUID().toString()).put("kind", kind).put("atMillis", System.currentTimeMillis())
        if (id != null) event.put("alarmId", id)
        if (scheduledAt != null) event.put("scheduledAtMillis", scheduledAt)
        if (error != null) event.put("error", error)
        if (kind != "screenOn") {
            val records = pending(context).put(event)
            val editor = context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).edit().putString("events", records.toString())
            if (kind == "alarmError") editor.putString("last_alarm_issue", event.toString())
            check(editor.commit()) { "알람 이벤트 저장 실패" }
        }
        handler.post { sink?.success(asMap(event)); if (kind == "alarmError") issueListener?.invoke() }
    }
    fun latestIssue(context: Context): JSONObject? {
        val items = pending(context)
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            if (item.optString("kind") == "alarmError") return item
        }
        return context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE).getString("last_alarm_issue", null)?.let { JSONObject(it) }
    }
    fun dismissIssue(context: Context, id: String) {
        acknowledge(context, id)
        val prefs = context.getSharedPreferences("morning_platform", Context.MODE_PRIVATE)
        val legacy = prefs.getString("last_alarm_issue", null)?.let { JSONObject(it) }
        if (legacy?.optString("eventId") == id) check(prefs.edit().remove("last_alarm_issue").commit())
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
    fun showWakeCandidate(id: String, at: Long) {
        require(id.isNotBlank() && at <= System.currentTimeMillis())
        val candidateChannel = "morning_wake_confirmation_v1"
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel(
                candidateChannel, "기상 확인 요청", NotificationManager.IMPORTANCE_DEFAULT
            ))
        }
        if ((Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            || !notifications.areNotificationsEnabled()
            || (Build.VERSION.SDK_INT >= 26 && notifications.getNotificationChannel(candidateChannel).importance == NotificationManager.IMPORTANCE_NONE)) {
            throw SecurityException("기상 확인 요청 알림 권한을 확인하세요.")
        }
        val open = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java).setData(Uri.parse("morning-routine://candidate")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, candidateChannel) else Notification.Builder(context)
        notifications.notify("wake-candidate", 1, builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("기상 여부를 확인해 주세요")
            .setContentText("화면 활동이 감지됐어요. 앱에서 확인하거나 취소해 주세요.")
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open).setOnlyAlertOnce(true).build())
    }
    fun clearWakeCandidate() { notifications.cancel("wake-candidate", 1) }

    private fun token(id: String, action: String, at: Long = 0, legacy: Boolean = false): PendingIntent {
        val data = Uri.Builder().scheme("morning-routine").authority(action).appendPath(id)
        if (!legacy) data.appendPath(at.toString())
        val intent = Intent(context, MorningAlarmReceiver::class.java).setAction(action)
            .setData(data.build())
            .putExtra("alarmId", id).putExtra("atMillis", at)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun state(): JSONObject = JSONObject(prefs.getString("alarms", "{}"))
    private fun save(state: JSONObject) { check(prefs.edit().putString("alarms", state.toString()).commit()) { "알람 상태 저장 실패" } }
    private fun readSlot(id: String): AlarmSlot? {
        val value = state().optJSONObject(id) ?: return null
        return AlarmSlot(id, value.getLong("atMillis"), value.getString("state"), value.optInt("tokenVersion", 1))
    }
    private fun arm(slot: AlarmSlot) {
        val show = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).setData(Uri.Builder().scheme("morning-routine").authority("open").appendPath(slot.id).build()), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.setAlarmClock(AlarmManager.AlarmClockInfo(slot.atMillis, show), token(slot.id, "fire", slot.atMillis, slot.tokenVersion < 2))
    }
    private fun cancelToken(slot: AlarmSlot) { manager.cancel(token(slot.id, "fire", slot.atMillis, slot.tokenVersion < 2)) }
    fun schedule(id: String, at: Long) {
        val backend = object : AlarmReplacementBackend {
            override fun permitted() = permissionState().values.all { it }
            override fun read(id: String) = readSlot(id)
            override fun arm(slot: AlarmSlot) = this@MorningAlarms.arm(slot)
            override fun cancel(slot: AlarmSlot) = cancelToken(slot)
            override fun write(slot: AlarmSlot) { save(state().put(slot.id, JSONObject().put("atMillis", slot.atMillis).put("state", slot.state).put("tokenVersion", slot.tokenVersion))) }
            override fun remove(id: String) { val values = state(); values.remove(id); save(values) }
            override fun stopRinging(id: String) { notifications.cancel(id, 0) }
        }
        val warnings = AlarmReplacement(backend, System::currentTimeMillis).schedule(id, at)
        if (warnings.isNotEmpty()) MorningEvents.emit(context, "alarmError", id, at, "previous_alarm_cleanup_failed")
    }
    fun cancel(id: String) {
        require(id.isNotBlank())
        readSlot(id)?.let { cancelToken(it) }
        // 이전 버전 PendingIntent도 남기지 않는다.
        manager.cancel(token(id, "fire", legacy = true))
        notifications.cancel(id, 0)
        val values = state(); values.remove(id); save(values)
    }
    fun permissionRisk(): AlarmSlot? {
        if (permissionState().values.all { it }) return null
        return state().keys().asSequence().mapNotNull { readSlot(it) }.firstOrNull()
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
        var attemptedAt: Long? = null
        try {
            if (intent.action != "fire" && !alarms.isRinging(id, intent.getLongExtra("atMillis", 0))) return
            when (intent.action) {
                "fire" -> alarms.fire(id, intent.getLongExtra("atMillis", 0))
                "dismiss" -> { alarms.cancel(id); MorningEvents.emit(context, "alarmDismissed", id) }
                "snooze" -> {
                    val at = System.currentTimeMillis() + 5 * 60_000L
                    attemptedAt = at
                    alarms.schedule(id, at)
                    MorningEvents.emit(context, "alarmSnoozed", id, at)
                }
            }
        } catch (error: Exception) { MorningEvents.emit(context, "alarmError", id, attemptedAt, if (intent.action == "snooze") "snooze_failed" else error.javaClass.simpleName) }
    }
}

internal class MorningPlatform(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val context = activity.applicationContext
    private val methods = MethodChannel(messenger, "morning_routine/platform")
    private val events = EventChannel(messenger, "morning_routine/platform_events")
    private val alarms = MorningAlarms(context)
    private var resumed = false
    private var issueDialog: AlertDialog? = null
    private var lastPermissionRisk: String? = null
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { if (intent.action == Intent.ACTION_SCREEN_ON) MorningEvents.emit(context, "screenOn") }
    }
    init {
        methods.setMethodCallHandler(this); events.setStreamHandler(this)
        MorningEvents.issueListener = { if (resumed) showIssue() }
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED) else context.registerReceiver(receiver, filter)
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { MorningEvents.sink = sink }
    override fun onCancel(arguments: Any?) { MorningEvents.sink = null }
    private val summaryId = 4821
    private val summaryLaunch = "open_routine_summary"
    private var lastSummary: Triple<String, String, Long>? = null

    private fun showRoutineSummary(title: String, body: String, expiresAt: Long) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        if (!manager.areNotificationsEnabled()) return
        val remaining = expiresAt - System.currentTimeMillis()
        if (remaining <= 0) {
            manager.cancel(summaryId)
            lastSummary = null
            return
        }
        val channelId = "routine_summary"
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "아침 루틴 요약", NotificationManager.IMPORTANCE_LOW)
            )
            if (manager.getNotificationChannel(channelId).importance == NotificationManager.IMPORTANCE_NONE) return
            Notification.Builder(context, channelId).setTimeoutAfter(remaining)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }
        val summary = Triple(title, body, expiresAt)
        if (lastSummary == summary && manager.activeNotifications.any { it.id == summaryId }) return
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(summaryLaunch, true)
        val pending = PendingIntent.getActivity(
            context, summaryId, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        manager.notify(
            summaryId,
            builder.setSmallIcon(android.R.drawable.ic_menu_today)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setContentIntent(pending)
                .build()
        )
        lastSummary = summary
    }

    private fun bedtimeArtwork(): Bitmap {
        val bitmap = Bitmap.createBitmap(800, 280, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val background = Color.rgb(27, 37, 66)
        canvas.drawColor(background)
        val x = 649f
        val y = 152f
        val radius = 78f
        paint.color = Color.rgb(255, 220, 140)
        canvas.drawCircle(x, y, radius, paint)
        paint.color = background
        canvas.drawCircle(x + radius * 0.46f, y - radius * 0.38f, radius * 0.86f, paint)
        paint.color = Color.rgb(255, 220, 140)
        canvas.drawCircle(x + radius * 0.9f, y - radius * 0.65f, radius * 0.09f, paint)
        canvas.drawCircle(x + radius * 1.35f, y - radius * 0.14f, radius * 0.06f, paint)
        paint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        paint.textSize = 29f
        canvas.drawText("지금 누우면 기상까지", 42f, 105f, paint)
        paint.typeface = Typeface.create("sans-serif", Typeface.BOLD)
        paint.textSize = 62f
        paint.color = Color.WHITE
        canvas.drawText("7시간 30분", 42f, 185f, paint)
        return bitmap
    }

    private fun showBedtimePreview(): String {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 208)
            return "permission_required"
        }
        if (!manager.areNotificationsEnabled()) return "blocked"

        val channelId = "bedtime_preview"
        val previewId = 4822
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "취침 알림 테스트", NotificationManager.IMPORTANCE_HIGH)
            )
            if (manager.getNotificationChannel(channelId).importance == NotificationManager.IMPORTANCE_NONE) return "blocked"
            Notification.Builder(context, channelId).setTimeoutAfter(300_000L)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND)
        }
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(summaryLaunch, true)
        val pending = PendingIntent.getActivity(
            context, previewId, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val body = "기상까지 7시간 30분 · 내일 오전 7:00"
        manager.cancel(previewId)
        manager.notify(
            previewId,
            builder.setSmallIcon(android.R.drawable.ic_menu_today)
                .setContentTitle("이제 슬슬 잘 시간이에요")
                .setContentText(body)
                .setStyle(
                    Notification.BigPictureStyle()
                        .bigPicture(bedtimeArtwork())
                        .setSummaryText("내일 오전 7:00 기상")
                )
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setShowWhen(false)
                .setContentIntent(pending)
                .build()
        )
        return "posted"
    }

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
                "showBedtimePreview" -> result.success(showBedtimePreview())
                "showRoutineSummary" -> {
                    showRoutineSummary(
                        requireNotNull(call.argument<String>("title")),
                        requireNotNull(call.argument<String>("body")),
                        requireNotNull(call.argument<Number>("expiresAt")).toLong()
                    )
                    result.success(null)
                }
                "clearRoutineSummary" -> {
                    context.getSystemService(NotificationManager::class.java).cancel(summaryId)
                    lastSummary = null
                    result.success(null)
                }
                "takeRoutineSummaryLaunch" -> {
                    val intent = activity.intent
                    val opened = intent?.getBooleanExtra(summaryLaunch, false) == true
                    if (opened) intent?.removeExtra(summaryLaunch)
                    result.success(opened)
                }
                "schedule" -> {
                    val id = requireNotNull(call.argument<String>("id"))
                    val at = requireNotNull(call.argument<Number>("atMillis")).toLong()
                    try { alarms.schedule(id, at); result.success(null) }
                    catch (error: Exception) { MorningEvents.emit(context, "alarmError", id, at, "schedule_failed"); throw error }
                }
                "cancel" -> { alarms.cancel(requireNotNull(call.argument<String>("id"))); result.success(null) }
                "showWakeCandidate" -> { alarms.showWakeCandidate(requireNotNull(call.argument<String>("id")), requireNotNull(call.argument<Number>("atMillis")).toLong()); result.success(null) }
                "clearWakeCandidate" -> { alarms.clearWakeCandidate(); result.success(null) }
                "pendingAlarmEvents" -> { val values = MorningEvents.pending(context); result.success((0 until values.length()).map { MorningEvents.asMap(values.getJSONObject(it)) }) }
                "acknowledgeAlarmEvent" -> { MorningEvents.acknowledge(context, requireNotNull(call.argument<String>("eventId"))); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: IllegalArgumentException) { result.error("invalid_argument", error.message, null) }
        catch (error: SecurityException) { result.error("permission_denied", error.message, null) }
        catch (error: Exception) { result.error("platform_error", error.message, null) }
    }
    fun onResume() {
        resumed = true
        val risk = alarms.permissionRisk()
        val signature = risk?.let { "${it.id}:${it.atMillis}:${alarms.permissionState()}" }
        if (risk != null && signature != lastPermissionRisk) {
            lastPermissionRisk = signature
            if (MorningEvents.latestIssue(context) == null) MorningEvents.emit(context, "alarmError", risk.id, risk.atMillis, "permission_changed")
        }
        if (risk == null) lastPermissionRisk = null
        showIssue()
    }
    fun onPause() { resumed = false }
    private fun showIssue() {
        if (!resumed || activity.isFinishing || activity.isDestroyed || issueDialog?.isShowing == true) return
        val issue = MorningEvents.latestIssue(context) ?: return
        val message = when (issue.optString("error")) {
            "notification_permission_denied" -> "알림 권한이 꺼져 알람의 소리와 진동을 전달하지 못했어요. 권한을 확인하고 알람을 다시 설정해 주세요."
            "permission_changed" -> "알람에 필요한 권한이 변경됐어요. 권한을 확인한 뒤 알람을 다시 설정해 주세요."
            "snooze_failed" -> "다시 울림을 예약하지 못했어요. 현재 알람 상태를 확인하고 다시 설정해 주세요."
            else -> "알람 적용에 문제가 있었어요. 알람 상태와 권한을 확인한 뒤 다시 예약해 주세요."
        }
        fun acknowledge() { MorningEvents.dismissIssue(context, issue.getString("eventId")); handlerAfterIssue() }
        issueDialog = AlertDialog.Builder(activity).setTitle("알람 상태를 확인해 주세요")
            .setMessage(message).setCancelable(false)
            .setPositiveButton("권한 설정") { _, _ ->
                acknowledge()
                val intent = if (Build.VERSION.SDK_INT >= 31 && !alarms.permissionState().getValue("exactAlarm"))
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                    else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                activity.startActivity(intent)
            }
            .setNegativeButton("확인") { _, _ -> acknowledge() }.show()
    }
    private fun handlerAfterIssue() { Handler(Looper.getMainLooper()).post { showIssue() } }
    fun close() {
        issueDialog?.dismiss()
        MorningEvents.issueListener = null
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
        MorningEvents.sink = null; context.unregisterReceiver(receiver)
    }
}

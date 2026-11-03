package io.github.hye6k.morning_routine

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray

object ProbeLog {
    fun append(context: Context, event: String) {
        val prefs = context.getSharedPreferences("android_probe", Context.MODE_PRIVATE)
        val previous = JSONArray(prefs.getString("events", "[]"))
        val next = JSONArray()
        for (i in maxOf(0, previous.length() - 199) until previous.length()) next.put(previous.getString(i))
        next.put("${System.currentTimeMillis()} $event")
        // 종료·재실행 실험에서 마지막 관측이 사라지지 않도록 동기 저장한다.
        prefs.edit().putString("events", next.toString()).commit()
    }
    fun text(context: Context): String {
        val data = JSONArray(context.getSharedPreferences("android_probe", Context.MODE_PRIVATE).getString("events", "[]"))
        return (0 until data.length()).joinToString("\n") { data.getString(it) }
    }
}

class ProbeActivity : Activity() {
    private lateinit var output: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var registered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            ProbeLog.append(context, "ACTIVITY_SIGNAL ${intent.action}; NOT_WAKE_CONFIRMATION")
            refresh()
        }
    }
    private val repaint = object : Runnable {
        override fun run() { refresh(); handler.postDelayed(this, 1000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 24, 24, 24) }
        column.addView(TextView(this).apply { text = "개발 전용 Android 실험\n활동 신호·알람 수신을 기록합니다. 실제 기상 확정이 아닙니다."; textSize = 19f })
        fun button(label: String, action: () -> Unit) {
            column.addView(Button(this).apply { text = label; setOnClickListener { action(); refresh() } })
        }
        button("정확한 알람 권한 설정") {
            if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
        }
        button("알림 권한 요청") {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 10)
        }
        button("30초 후 알람 예약") { schedule(30) }
        button("알람 취소") { cancelAlarm() }
        button("기록 지우기") { getSharedPreferences("android_probe", MODE_PRIVATE).edit().clear().commit() }
        output = TextView(this).apply { setTextIsSelectable(true); textSize = 12f }
        column.addView(output)
        setContentView(ScrollView(this).apply { addView(column) })
        val filter = IntentFilter().apply { addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED) else registerReceiver(receiver, filter)
        registered = true
        ProbeLog.append(this, "ACTIVITY_CREATED; DYNAMIC_RECEIVER_ACTIVITY_LIFETIME_ONLY")
        if (savedInstanceState == null) handleAction(intent)
        else ProbeLog.append(this, "ACTIVITY_RESTORED; NO_COMMAND_REPLAY")
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); handleAction(intent) }
    private fun handleAction(intent: Intent) {
        val action = intent.getStringExtra("action")
        val seconds = intent.getIntExtra("delay_seconds", 30)
        intent.removeExtra("action")
        intent.removeExtra("delay_seconds")
        when (action) {
            "schedule" -> schedule(seconds)
            "cancel" -> cancelAlarm()
        }
        refresh()
    }
    override fun onResume() { super.onResume(); handler.post(repaint) }
    override fun onPause() { handler.removeCallbacks(repaint); super.onPause() }
    override fun onDestroy() {
        handler.removeCallbacks(repaint)
        if (registered) unregisterReceiver(receiver)
        super.onDestroy()
    }

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(this, 7, Intent(this, ProbeAlarmReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun schedule(seconds: Int) {
        if (seconds !in 5..3600) { ProbeLog.append(this, "INVALID_DELAY"); return }
        val manager = getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT >= 31 && !manager.canScheduleExactAlarms()) { ProbeLog.append(this, "EXACT_ALARM_PERMISSION_DENIED"); return }
        val at = System.currentTimeMillis() + seconds * 1000L
        val show = PendingIntent.getActivity(this, 7, Intent(this, ProbeActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), alarmIntent())
            ProbeLog.append(this, "ALARM_SCHEDULED at=$at")
        } catch (error: SecurityException) { ProbeLog.append(this, "ALARM_SECURITY_ERROR ${error.javaClass.simpleName}") }
    }
    private fun cancelAlarm() {
        getSystemService(AlarmManager::class.java).cancel(alarmIntent())
        ProbeLog.append(this, "ALARM_CANCELLED; NOT_WAKE_CONFIRMATION")
    }
    private fun refresh() {
        if (::output.isInitialized) output.text = ProbeLog.text(this)
    }
}

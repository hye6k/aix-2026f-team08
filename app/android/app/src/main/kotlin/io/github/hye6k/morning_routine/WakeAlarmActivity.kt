package io.github.hye6k.morning_routine

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class WakeAlarmActivity : Activity() {
    private var alarmId: String? = null
    private var scheduledAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        alarmId = intent.getStringExtra("alarmId")
        scheduledAt = intent.getLongExtra("atMillis", 0)
        val id = alarmId
        if (id == null || !RoutineWakeAlarm.owns(id) ||
            !MorningAlarms(this).isRinging(id, scheduledAt)
        ) {
            finish()
            return
        }
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        val screen = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.rgb(27, 37, 66))
        }
        screen.addView(TextView(this).apply {
            text = DateFormat.getTimeFormat(this@WakeAlarmActivity)
                .format(java.util.Date(scheduledAt))
            textSize = 48f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        })
        screen.addView(TextView(this).apply {
            text = if (id == RoutineWakeAlarm.PREVIEW_ID) "기상 알람 테스트" else "기상 알람"
            textSize = 20f
            setTextColor(Color.rgb(255, 220, 140))
            setPadding(0, dp(8), 0, dp(24))
            gravity = Gravity.CENTER
        })
        screen.addView(Button(this).apply {
            text = "기상 확인"
            minimumHeight = dp(56)
            setOnClickListener {
                isEnabled = false
                sendBroadcast(
                    Intent(this@WakeAlarmActivity, MorningAlarmReceiver::class.java)
                        .setAction("dismiss")
                        .putExtra("alarmId", id)
                        .putExtra("atMillis", scheduledAt)
                )
                finish()
            }
        })
        setContentView(screen)
    }

    override fun onResume() {
        super.onResume()
        val id = alarmId
        if (id == null || !MorningAlarms(this).isRinging(id, scheduledAt)) finish()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

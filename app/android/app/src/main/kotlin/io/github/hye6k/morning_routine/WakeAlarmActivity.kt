package io.github.hye6k.morning_routine

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
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
        val ink = Color.rgb(19, 29, 49)
        val amber = Color.rgb(255, 220, 140)
        val screen = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(24), dp(28), dp(32))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(ink, Color.rgb(43, 55, 89))
            )
            if (Build.VERSION.SDK_INT >= 30) {
                setOnApplyWindowInsetsListener { view, insets ->
                    val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                    view.setPadding(dp(28) + bars.left, dp(24) + bars.top, dp(28) + bars.right, dp(32) + bars.bottom)
                    insets
                }
            }
        }
        val timePanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        timePanel.addView(ImageView(this).apply {
            setImageResource(R.drawable.ic_routine_sunrise)
            imageTintList = ColorStateList.valueOf(amber)
            importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(32), dp(32)))
        timePanel.addView(TextView(this).apply {
            text = DateFormat.getTimeFormat(this@WakeAlarmActivity)
                .format(java.util.Date(scheduledAt))
            textSize = 62f
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            setTextColor(Color.WHITE)
            setPadding(0, dp(12), 0, dp(4))
            gravity = Gravity.CENTER
        })
        timePanel.addView(TextView(this).apply {
            text = if (id == RoutineWakeAlarm.PREVIEW_ID) "기상 알람 테스트" else "기상 알람"
            textSize = 16f
            setTextColor(Color.rgb(205, 214, 236))
            gravity = Gravity.CENTER
        })
        screen.addView(timePanel, LinearLayout.LayoutParams(-1, 0, 1f))
        screen.addView(Button(this).apply {
            text = "기상 확인"
            textSize = 18f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(ink)
            minimumHeight = dp(56)
            setPadding(dp(20), dp(12), dp(20), dp(12))
            backgroundTintList = null
            background = RippleDrawable(
                ColorStateList.valueOf(0x24131d31),
                GradientDrawable().apply {
                    setColor(amber)
                    cornerRadius = dp(28).toFloat()
                },
                null,
            )
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
        }, LinearLayout.LayoutParams(-1, -2))
        setContentView(screen)
    }

    override fun onResume() {
        super.onResume()
        val id = alarmId
        if (id == null || !MorningAlarms(this).isRinging(id, scheduledAt)) finish()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

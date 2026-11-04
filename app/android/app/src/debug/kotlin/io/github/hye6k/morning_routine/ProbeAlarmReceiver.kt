package io.github.hye6k.morning_routine

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

class ProbeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ProbeLog.append(context, "ALARM_RECEIVED; NOT_WAKE_CONFIRMATION")
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = "android_probe_alarm"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, "개발 실험 알람", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                enableVibration(true)
            })
        }
        val allowed = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (allowed) {
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
            manager.notify(7, builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("개발용 알람 실험")
                .setContentText("알람 수신 확인: 실제 기상 확정 아님").setAutoCancel(true).build())
            ProbeLog.append(context, "NOTIFICATION_REQUESTED; ACTUAL_SOUND_UNVERIFIED")
        } else ProbeLog.append(context, "NOTIFICATION_PERMISSION_DENIED")
        @Suppress("DEPRECATION")
        val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createOneShot(1000, VibrationEffect.DEFAULT_AMPLITUDE)) else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(1000)
        }
        ProbeLog.append(context, "VIBRATION_REQUESTED has_vibrator=${vibrator.hasVibrator()}; ACTUAL_VIBRATION_UNVERIFIED")
    }
}

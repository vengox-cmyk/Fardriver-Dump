package com.arcdash.arcdash

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class ArcDashForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "arcdash_controller"
        const val NOTIFICATION_ID = 4101
        const val ACTION_STOP = "com.arcdash.arcdash.STOP_SERVICE"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, notification("Controller-Verbindung aktiv"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) stopSelf()
        // Process death must not silently resume a write or reconnect transaction.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ArcDash Controller",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Status der BLE-Controllerverbindung"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun notification(text: String): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("ArcDash")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
    }
}

package com.example.shotkeeper

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.*
import android.util.Log

class DeletionJobService : Service() {
    companion object {
        private const val CHANNEL_ID = "deletion_channel"
        private const val NOTIFICATION_ID = 102
        private const val TAG = "DeletionJob"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("ShotKeeper")
            .setContentText("Managing screenshot retention...")
            .setSmallIcon(android.R.drawable.ic_menu_delete)
            .build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Deletion Job", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val delaySec = intent?.getLongExtra("delay_seconds", 0L) ?: 0L
        val path = intent?.getStringExtra("screenshot_path")
        if (path != null) {
            DeletionManager.scheduleDeletion(this, path, delaySec)
        }
        DeletionManager.checkAndExecuteDueDeletions(this)
        stopSelf()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() { super.onDestroy(); Log.d(TAG, "DeletionJobService destroyed") }
}

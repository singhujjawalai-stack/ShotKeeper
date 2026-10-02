package com.example.shotkeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class DeletionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        val action = intent?.action
        Log.i("DeletionAlarmReceiver", "Received action: $action")
        DeletionManager.checkAndExecuteDueDeletions(context)
        DeletionManager.scheduleNextAlarm(context)
    }
}

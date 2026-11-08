package com.example.shotkeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Handles all alarm-driven work for ShotKeeper:
 *  - CHECK_DELETIONS: run due deletions, arm the next one, refresh service notification
 *  - WATCHDOG: periodic self-rescheduling alarm that revives the detector service
 *    if the system or an OEM task killer killed it (fixes "app must be launched
 *    for screenshots to be detected")
 *  - RESTART_SERVICE: one-shot restart, e.g. after the app task is swiped away
 *  - BOOT_COMPLETED / MY_PACKAGE_REPLACED: restart the detector after reboot or app update
 */
class DeletionAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "DeletionAlarmReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        val action = intent?.action
        Log.i(TAG, "Received action: $action")
        when (action) {
            DeletionManager.ACTION_CHECK_DELETIONS -> {
                DeletionManager.checkAndExecuteDueDeletions(context)
                DeletionManager.cleanExpiredTrash(context)
                DeletionManager.scheduleNextAlarm(context)
                startDetectorIfEnabled(context)
            }
            DeletionManager.ACTION_WATCHDOG -> {
                // Self-reschedule first so the watchdog keeps firing even if
                // this particular start attempt is blocked by the OS.
                DeletionManager.scheduleWatchdog(context)
                startDetectorIfEnabled(context)
            }
            DeletionManager.ACTION_RESTART_SERVICE -> startDetectorIfEnabled(context)
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> startDetectorIfEnabled(context)
            else -> Log.i(TAG, "Unknown action ignored: $action")
        }
    }

    private fun startDetectorIfEnabled(context: Context) {
        if (!DeletionManager.isDetectorEnabled(context)) return
        try {
            val serviceIntent = Intent(context, ScreenshotDetectorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Could not (re)start detector service", e)
        }
    }
}

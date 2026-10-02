package com.example.shotkeeper

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import org.json.JSONObject
import java.io.File

object DeletionManager {
    private const val TAG = "DeletionManager"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_SCHEDULED = "flutter.shot_keeper_scheduled_deletions"
    const val ACTION_CHECK_DELETIONS = "com.example.shotkeeper.CHECK_DELETIONS"

    @Synchronized
    fun getScheduledDeletions(context: Context): Map<String, Long> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonStr = prefs.getString(KEY_SCHEDULED, "{}") ?: "{}"
        val map = mutableMapOf<String, Long>()
        try {
            val json = JSONObject(jsonStr)
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = json.getLong(key)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading scheduled deletions JSON", e)
        }
        return map
    }

    @Synchronized
    fun saveScheduledDeletions(context: Context, map: Map<String, Long>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = JSONObject()
        for ((path, timeMs) in map) {
            json.put(path, timeMs)
        }
        prefs.edit().putString(KEY_SCHEDULED, json.toString()).apply()
    }

    @Synchronized
    fun scheduleDeletion(context: Context, path: String, delaySeconds: Long): Long {
        val targetMs = System.currentTimeMillis() + (delaySeconds * 1000L)
        val map = getScheduledDeletions(context).toMutableMap()
        map[path] = targetMs
        saveScheduledDeletions(context, map)
        Log.i(TAG, "Scheduled single deletion for: $path at $targetMs (in ${delaySeconds}s)")
        scheduleNextAlarm(context)
        return targetMs
    }

    @Synchronized
    fun scheduleBatchDeletion(context: Context, paths: List<String>, delaySeconds: Long): Long {
        val targetMs = System.currentTimeMillis() + (delaySeconds * 1000L)
        val map = getScheduledDeletions(context).toMutableMap()
        for (path in paths) {
            map[path] = targetMs
        }
        saveScheduledDeletions(context, map)
        Log.i(TAG, "Scheduled batch deletion for ${paths.size} items at $targetMs (in ${delaySeconds}s)")
        scheduleNextAlarm(context)
        return targetMs
    }

    @Synchronized
    fun cancelSchedule(context: Context, path: String) {
        val map = getScheduledDeletions(context).toMutableMap()
        if (map.containsKey(path)) {
            map.remove(path)
            saveScheduledDeletions(context, map)
            Log.i(TAG, "Cancelled deletion schedule for: $path")
            scheduleNextAlarm(context)
        }
    }

    fun deleteFileNow(context: Context, path: String): Boolean {
        var success = false
        try {
            val file = File(path)
            if (file.exists()) {
                success = file.delete()
                Log.d(TAG, "File.delete() result for $path: $success")
            } else {
                success = true
            }

            // Also remove from MediaStore
            try {
                val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val deletedRows = context.contentResolver.delete(
                    uri,
                    "${MediaStore.Images.Media.DATA} = ?",
                    arrayOf(path)
                )
                Log.d(TAG, "MediaStore delete rows: $deletedRows for $path")
            } catch (e: Exception) {
                Log.w(TAG, "MediaStore deletion failed for $path", e)
            }

            // Trigger MediaScanner
            MediaScannerConnection.scanFile(context, arrayOf(path), null, null)

            // Remove from scheduled map if present
            cancelSchedule(context, path)
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting file $path", e)
        }
        return success
    }

    @Synchronized
    fun checkAndExecuteDueDeletions(context: Context): Int {
        val now = System.currentTimeMillis()
        val currentMap = getScheduledDeletions(context)
        if (currentMap.isEmpty()) return 0

        val dueItems = mutableListOf<String>()
        val updatedMap = mutableMapOf<String, Long>()

        for ((path, targetMs) in currentMap) {
            if (now >= targetMs) {
                dueItems.add(path)
            } else {
                updatedMap[path] = targetMs
            }
        }

        if (dueItems.isNotEmpty()) {
            saveScheduledDeletions(context, updatedMap)
            Log.i(TAG, "Executing due deletions for ${dueItems.size} items: $dueItems")
            for (path in dueItems) {
                try {
                    val file = File(path)
                    if (file.exists()) {
                        val deleted = file.delete()
                        Log.i(TAG, "Deleted due file: $path (success=$deleted)")
                    }
                    try {
                        context.contentResolver.delete(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            "${MediaStore.Images.Media.DATA} = ?",
                            arrayOf(path)
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "MediaStore deletion failed for $path", e)
                    }
                    MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to delete due file: $path", e)
                }
            }
            scheduleNextAlarm(context)
        }

        return dueItems.size
    }

    fun scheduleNextAlarm(context: Context) {
        val map = getScheduledDeletions(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, DeletionAlarmReceiver::class.java).apply {
            action = ACTION_CHECK_DELETIONS
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            1001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (map.isEmpty()) {
            alarmManager.cancel(pendingIntent)
            return
        }

        val minTargetMs = map.values.minOrNull() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, minTargetMs, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, minTargetMs, pendingIntent)
            }
            Log.d(TAG, "Scheduled next alarm for target timestamp: $minTargetMs (now=${System.currentTimeMillis()})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set exact alarm, trying standard alarm", e)
            try {
                alarmManager.set(AlarmManager.RTC_WAKEUP, minTargetMs, pendingIntent)
            } catch (ex: Exception) {
                Log.e(TAG, "Failed to set standard alarm", ex)
            }
        }
    }
}

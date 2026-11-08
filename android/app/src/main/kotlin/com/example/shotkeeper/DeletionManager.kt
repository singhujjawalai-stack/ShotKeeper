package com.example.shotkeeper

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import org.json.JSONObject
import java.io.File

object DeletionManager {
    private const val TAG = "DeletionManager"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_SCHEDULED = "flutter.shot_keeper_scheduled_deletions"
    private const val KEY_TRASH = "flutter.shot_keeper_trash"
    private const val KEY_PINNED = "flutter.shot_keeper_pinned"
    private const val DETECTOR_PREFS = "ShotKeeperDetector"
    private const val KEY_DETECTOR_ENABLED = "detector_enabled"

    // Matches ScreenshotDetectorService's keys so deletions don't re-alert
    private const val KEY_PROCESSED = "processed_screenshot_ids"
    private const val KEY_BASELINED = "screenshots_baselined"

    const val ACTION_CHECK_DELETIONS = "com.example.shotkeeper.CHECK_DELETIONS"
    const val ACTION_WATCHDOG = "com.example.shotkeeper.WATCHDOG"
    const val ACTION_RESTART_SERVICE = "com.example.shotkeeper.RESTART_SERVICE"
    private const val WATCHDOG_INTERVAL_MS = 15L * 60L * 1000L

    /** How long a trashed screenshot survives before hard deletion. */
    const val TRASH_GRACE_MS = 7L * 24L * 60L * 60L * 1000L

    // ---- Scheduled deletions -------------------------------------------------

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

    // ---- Store access helpers ------------------------------------------------

    @Synchronized
    fun getTrashMap(context: Context): JSONObject {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return try {
            JSONObject(prefs.getString(KEY_TRASH, "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
    }

    @Synchronized
    private fun saveTrashMap(context: Context, obj: JSONObject) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_TRASH, obj.toString()).apply()
    }

    private fun getPinnedMap(context: Context): JSONObject {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return try {
            JSONObject(prefs.getString(KEY_PINNED, "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
    }

    private fun savePinnedMap(context: Context, obj: JSONObject) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_PINNED, obj.toString()).apply()
    }

    fun isPinned(context: Context, path: String): Boolean = getPinnedMap(context).has(path)

    @Synchronized
    fun setPinned(context: Context, path: String, pinned: Boolean) {
        val map = getPinnedMap(context)
        val changed = if (pinned) !map.has(path) else map.has(path)
        if (pinned) map.put(path, 1) else map.remove(path)
        if (changed) {
            savePinnedMap(context, map)
            if (pinned) {
                // Pin vetoes both running timers and auto-pilot
                cancelSchedule(context, path)
            }
            Log.i(TAG, "Pin set for $path: $pinned")
            scheduleNextAlarm(context)
        }
    }

    // ---- Trash ---------------------------------------------------------------

    /**
     * Moves a file into the app's private trash folder instead of deleting it.
     * Original path is the store key so the UI can restore by it.
     */
    @Synchronized
    fun moveToTrash(context: Context, originalPath: String): Boolean {
        try {
            val file = File(originalPath)
            if (!file.exists()) return true
            val trashDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "ShotKeeperTrash")
            if (!trashDir.exists()) trashDir.mkdirs()
            val dest = File(trashDir, System.currentTimeMillis().toString() + "_" + file.name)
            val moved = file.renameTo(dest)
            if (!moved) {
                // Cross-volume safety net: copy then delete
                dest.writeBytes(file.readBytes())
                file.delete()
            }

            val trashMap = getTrashMap(context)
            trashMap.put(
                originalPath,
                JSONObject()
                    .put("e", System.currentTimeMillis() + TRASH_GRACE_MS)
                    .put("t", dest.absolutePath)
                    .put("o", file.parent ?: "")
                    .put("n", file.name)
            )
            saveTrashMap(context, trashMap)

            // Remove the MediaStore entry pointing to the old location
            try {
                context.contentResolver.delete(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    "${MediaStore.Images.Media.DATA} = ?",
                    arrayOf(originalPath)
                )
            } catch (e: Exception) {
                Log.w(TAG, "MediaStore delete failed for $originalPath", e)
            }
            MediaScannerConnection.scanFile(context, arrayOf(originalPath, dest.absolutePath), null, null)

            // No longer needs a deletion timer
            cancelSchedule(context, originalPath)
            scheduleNextAlarm(context)
            Log.i(TAG, "Moved to trash: $originalPath -> ${dest.absolutePath}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "moveToTrash failed for $originalPath", e)
            return false
        }
    }

    @Synchronized
    fun restoreFromTrash(context: Context, originalPath: String): Boolean {
        try {
            val trashMap = getTrashMap(context)
            val meta = trashMap.optJSONObject(originalPath) ?: return false
            val trashFile = File(meta.optString("t"))
            if (!trashFile.exists()) {
                trashMap.remove(originalPath)
                saveTrashMap(context, trashMap)
                return true
            }
            val parentDir = File(meta.optString("o").ifBlank { trashFile.parent ?: "/storage/emulated/0/Pictures" })
            if (!parentDir.exists()) parentDir.mkdirs()

            val originalName = meta.optString("n")
            val dot = originalName.lastIndexOf('.')
            val base = if (dot > 0) originalName.substring(0, dot) else originalName
            val ext = if (dot > 0) originalName.substring(dot) else ""
            var finalTarget = File(parentDir, originalName)
            var idx = 1
            while (finalTarget.exists()) {
                finalTarget = File(parentDir, "$base ($idx)$ext")
                idx++
            }
            val moved = trashFile.renameTo(finalTarget)
            if (!moved) {
                finalTarget.writeBytes(trashFile.readBytes())
                trashFile.delete()
            }
            trashMap.remove(originalPath)
            saveTrashMap(context, trashMap)

            // Mark the restored file as already-seen so the detector does not
            // fire a new "screenshot detected" alert for it (it gets a new ID).
            MediaScannerConnection.scanFile(context, arrayOf(finalTarget.absolutePath), null) { _, uri ->
                if (uri != null) {
                    try {
                        val dPrefs = context.getSharedPreferences(DETECTOR_PREFS, Context.MODE_PRIVATE)
                        val processed = dPrefs.getStringSet(KEY_PROCESSED, emptySet())?.toMutableSet()
                            ?: mutableSetOf()
                        processed.add(uri.toString())
                        dPrefs.edit().putStringSet(KEY_PROCESSED, processed).apply()
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not mark restored file as processed", e)
                    }
                }
            }
            MediaScannerConnection.scanFile(context, arrayOf(trashFile.absolutePath), null, null)
            scheduleNextAlarm(context)
            Log.i(TAG, "Restored from trash: $originalPath -> ${finalTarget.absolutePath}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "restoreFromTrash failed for $originalPath", e)
            return false
        }
    }

    /** Hard-deletes every trash item past its grace period. Returns removed count. */
    @Synchronized
    fun cleanExpiredTrash(context: Context): Int {
        val now = System.currentTimeMillis()
        val trashMap = getTrashMap(context)
        var removed = 0
        val keys = mutableListOf<String>()
        val keyIter = trashMap.keys()
        while (keyIter.hasNext()) keys.add(keyIter.next())
        for (key in keys) {
            val meta = trashMap.optJSONObject(key) ?: continue
            if (now >= meta.optLong("e")) {
                val trashFile = File(meta.optString("t"))
                val pathForScan = trashFile.absolutePath
                trashFile.delete()
                MediaScannerConnection.scanFile(context, arrayOf(pathForScan), null, null)
                trashMap.remove(key)
                removed++
            }
        }
        if (removed > 0) {
            saveTrashMap(context, trashMap)
            Log.i(TAG, "Cleaned $removed expired trash items")
            scheduleNextAlarm(context)
        }
        return removed
    }

    /** Empties the entire trash. Returns removed count. */
    @Synchronized
    fun emptyTrash(context: Context): Int {
        val trashMap = getTrashMap(context)
        var removed = 0
        val keys = mutableListOf<String>()
        val keyIter = trashMap.keys()
        while (keyIter.hasNext()) keys.add(keyIter.next())
        for (key in keys) {
            val meta = trashMap.optJSONObject(key) ?: continue
            val trashFile = File(meta.optString("t"))
            val pathForScan = trashFile.absolutePath
            trashFile.delete()
            MediaScannerConnection.scanFile(context, arrayOf(pathForScan), null, null)
            trashMap.remove(key)
            removed++
        }
        if (removed > 0) {
            saveTrashMap(context, trashMap)
            Log.i(TAG, "Emptied trash: $removed items")
            scheduleNextAlarm(context)
        }
        return removed
    }

    @Synchronized
    fun hardDeleteTrashItem(context: Context, originalPath: String): Boolean {
        val trashMap = getTrashMap(context)
        val meta = trashMap.optJSONObject(originalPath) ?: return false
        val trashFile = File(meta.optString("t"))
        val pathForScan = trashFile.absolutePath
        val deleted = !trashFile.exists() || trashFile.delete()
        trashMap.remove(originalPath)
        saveTrashMap(context, trashMap)
        MediaScannerConnection.scanFile(context, arrayOf(pathForScan), null, null)
        Log.i(TAG, "Hard-deleted trash item: $originalPath (success=$deleted)")
        scheduleNextAlarm(context)
        return deleted
    }

    // ---- Due deletion execution ----------------------------------------------

    /** Returns (deletedCount, failedPaths). Failed items stay scheduled and are retried later. */
    @Synchronized
    fun checkAndExecuteDueDeletions(context: Context): Pair<Int, List<String>> {
        val now = System.currentTimeMillis()
        val currentMap = getScheduledDeletions(context)
        if (currentMap.isEmpty()) return 0 to emptyList()

        val pinned = getPinnedMap(context)
        val dueItems = mutableListOf<String>()
        val updatedMap = mutableMapOf<String, Long>()
        var deletedCount = 0
        val failed = mutableListOf<String>()

        for ((path, targetMs) in currentMap) {
            if (now >= targetMs) {
                if (pinned.has(path)) {
                    // User asked to keep this forever: silently unschedule
                    Log.i(TAG, "Skipping due deletion for pinned item: $path")
                } else {
                    dueItems.add(path)
                }
            } else {
                updatedMap[path] = targetMs
            }
        }

        if (dueItems.isNotEmpty()) {
            val retryMap = mutableMapOf<String, Long>()
            saveScheduledDeletions(context, updatedMap)
            Log.i(TAG, "Executing due deletions for ${dueItems.size} items: $dueItems")
            for (path in dueItems) {
                if (moveToTrash(context, path)) {
                    deletedCount++
                } else {
                    failed.add(path)
                    // Keep it scheduled but push the deadline one minute out so the
                    // UI doesn't hammer check_due_deletions every tick while retrying.
                    retryMap[path] = now + 60_000L
                    Log.e(TAG, "Failed to delete due item: $path")
                }
            }
            if (retryMap.isNotEmpty()) {
                saveScheduledDeletions(context, updatedMap + retryMap)
            }
            scheduleNextAlarm(context)
        }

        return deletedCount to failed
    }

    // ---- Alarm scheduling ------------------------------------------------------

    fun scheduleNextAlarm(context: Context) {
        val map = getScheduledDeletions(context)
        val trash = getTrashMap(context)
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

        val times = mutableListOf<Long>()
        times.addAll(map.values)
        val keyIter = trash.keys()
        while (keyIter.hasNext()) {
            val meta = trash.optJSONObject(keyIter.next())
            if (meta != null) times.add(meta.optLong("e"))
        }

        if (times.isEmpty()) {
            alarmManager.cancel(pendingIntent)
            return
        }

        val minTargetMs = times.minOrNull() ?: return
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

    // ---- Detector service lifecycle helpers ------------------------------------

    fun isDetectorEnabled(context: Context): Boolean =
        context.getSharedPreferences(DETECTOR_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_DETECTOR_ENABLED, false)

    fun setDetectorEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(DETECTOR_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DETECTOR_ENABLED, enabled).apply()
        if (enabled) scheduleWatchdog(context) else cancelWatchdog(context)
    }

    /**
     * Periodic self-rescheduling exact alarm that revives the detector service
     * if the process was killed (system, Doze, OEM task killers). Deleting alarms
     * use setExactAndAllowWhileIdle, which puts the app on the temporary
     * allowlist for foreground-service background starts.
     */
    fun scheduleWatchdog(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val at = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS
        val pi = watchdogPendingIntent(context)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Watchdog exact alarm failed, falling back", e)
            try { am.set(AlarmManager.RTC_WAKEUP, at, pi) } catch (ex: Exception) {
                Log.e(TAG, "Watchdog alarm failed", ex)
            }
        }
    }

    fun cancelWatchdog(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)
            ?.cancel(watchdogPendingIntent(context))
    }

    private fun watchdogPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DeletionAlarmReceiver::class.java).apply { action = ACTION_WATCHDOG }
        return PendingIntent.getBroadcast(
            context, 1002, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** One-shot restart used when the app task is swiped away. */
    fun scheduleServiceRestart(context: Context, delayMs: Long = 3000L) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, DeletionAlarmReceiver::class.java).apply { action = ACTION_RESTART_SERVICE }
        val pi = PendingIntent.getBroadcast(
            context, 1003, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val at = System.currentTimeMillis() + delayMs
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Restart alarm fallback", e)
            try { am.set(AlarmManager.RTC_WAKEUP, at, pi) } catch (ex: Exception) {
                Log.e(TAG, "Restart alarm failed", ex)
            }
        }
    }
}

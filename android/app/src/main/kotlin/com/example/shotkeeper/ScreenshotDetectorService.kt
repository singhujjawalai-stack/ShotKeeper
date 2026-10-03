package com.example.shotkeeper

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.MediaStore
import android.util.Log
import java.io.File

class ScreenshotDetectorService : Service() {
    companion object {
        const val CHANNEL_ID = "shotkeeper_service"
        const val NOTIFICATION_ID = 101
        private const val ALERT_CHANNEL_ID = "shotkeeper_screenshot_alerts"
        private const val TAG = "ScreenshotDetector"
        private const val PREFS = "ShotKeeperDetector"
        private const val KEY_BASELINED = "screenshots_baselined"
        private const val KEY_PROCESSED = "processed_screenshot_ids"
        private const val KEY_LAST_SCAN = "last_scan_seconds"
        private const val POLL_INTERVAL_MS = 10_000L
    }

    private lateinit var workerThread: HandlerThread
    private lateinit var worker: Handler
    private var observer: ContentObserver? = null
    private var count = 0
    private var processedIds = mutableSetOf<String>()
    private var lastScanSeconds = 0L
    private var baselinePending = true

    override fun onCreate() {
        super.onCreate()
        val logFile = File(getExternalFilesDir(null), "service_verification_log.txt")
        logFile.appendText("[${System.currentTimeMillis()}] SERVICE CREATED\n")
        createNotificationChannels()
        startForeground(NOTIFICATION_ID, buildStatusNotification())
        workerThread = HandlerThread("ShotKeeperMediaScan").also { it.start() }
        worker = Handler(workerThread.looper)
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        baselinePending = !prefs.getBoolean(KEY_BASELINED, false)
        processedIds = prefs.getStringSet(KEY_PROCESSED, emptySet())?.toMutableSet() ?: mutableSetOf()
        lastScanSeconds = prefs.getLong(KEY_LAST_SCAN, System.currentTimeMillis() / 1000L)
        count = getFlutterCount()
        updateStatusNotification()
        registerObserver()
        worker.post(scanRunnable)
    }

    private val scanRunnable = object : Runnable {
        override fun run() {
            scanMediaStore()
            worker.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private fun registerObserver() {
        observer = object : ContentObserver(worker) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                Log.d(TAG, "MediaStore changed: $uri")
                worker.removeCallbacks(scanRunnable)
                worker.postDelayed(scanRunnable, 700L)
            }
        }
        contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer!!)
    }

    private fun scanMediaStore() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val scanStart = System.currentTimeMillis() / 1000L
        val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.RELATIVE_PATH,
        ) else arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATA,
        )
        val selection = if (baselinePending) null else "${MediaStore.Images.Media.DATE_ADDED} >= ?"
        val args = if (baselinePending) null else arrayOf((lastScanSeconds - 2L).coerceAtLeast(0L).toString())
        val found = mutableListOf<Pair<String, String>>()
        var rowCount = 0

        try {
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                args,
                "${MediaStore.Images.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val pathColumn = cursor.getColumnIndex(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        MediaStore.Images.Media.RELATIVE_PATH else MediaStore.Images.Media.DATA
                )
                while (cursor.moveToNext()) {
                    rowCount++
                    val id = cursor.getLong(idColumn).toString()
                    val name = cursor.getString(nameColumn).orEmpty()
                    val path = if (pathColumn >= 0) cursor.getString(pathColumn).orEmpty() else ""
                    if (!isScreenshot(name, path)) continue
                    val uri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id).toString()
                    if (baselinePending) processedIds.add(uri)
                    else if (processedIds.add(uri)) found.add(uri to name)
                }
            }
        } catch (error: Exception) {
            Log.e(TAG, "MediaStore scan failed", error)
            return
        }

        Log.d(TAG, "MediaStore scan complete: rows=$rowCount newScreenshots=${found.size} baseline=$baselinePending")

        val logFile = File(getExternalFilesDir(null), "service_verification_log.txt")
        logFile.appendText("[${System.currentTimeMillis()}] SCAN: found=${found.size} processed=${processedIds.size} baselinePending=$baselinePending\n")
        if (baselinePending) {
            baselinePending = false
            prefs.edit().putBoolean(KEY_BASELINED, true).apply()
        }
        lastScanSeconds = scanStart
        prefs.edit().putStringSet(KEY_PROCESSED, processedIds.toSet()).putLong(KEY_LAST_SCAN, lastScanSeconds).apply()
        found.forEach { (uri, name) -> reportScreenshot(uri, name) }
    }

    private fun isScreenshot(displayName: String, relativePath: String): Boolean {
        val name = displayName.lowercase()
        return relativePath.contains("screenshots", ignoreCase = true) ||
            name.contains("screenshot") || name.contains("screen_shot") || name.contains("screencap")
    }

    private fun reportScreenshot(uri: String, displayName: String) {
        val path = getPathFromUri(uri)
        val logFile = File(getExternalFilesDir(null), "service_verification_log.txt")
        logFile.appendText("[${System.currentTimeMillis()}] REPORT: $displayName path=$path count=${count+1}\n")
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        count = flutterPrefs.getInt("flutter.shot_keeper_screenshot_count", 0) + 1
        flutterPrefs.edit().putInt("flutter.shot_keeper_screenshot_count", count).apply()
        Log.i(TAG, "Detected screenshot: $displayName ($uri), count=$count")
        updateStatusNotification()

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("action", "schedule_screenshot")
            putExtra("screenshot_path", path)
            putExtra("screenshot_name", displayName)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, uri.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alert = Notification.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setContentTitle("Screenshot detected")
            .setContentText("Tap to schedule deletion for $displayName")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(Notification.PRIORITY_HIGH)
            .build()
        getSystemService(NotificationManager::class.java).notify(uri.hashCode(), alert)
    }

    private fun getPathFromUri(uriString: String): String? = try {
        contentResolver.query(Uri.parse(uriString), arrayOf(MediaStore.Images.Media.DATA), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (error: Exception) {
        Log.w(TAG, "Could not resolve screenshot path", error)
        null
    }

    private fun getFlutterCount(): Int = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        .getInt("flutter.shot_keeper_screenshot_count", 0)

    private fun buildStatusNotification(): Notification {
        val scheduled = DeletionManager.getScheduledDeletions(this)
        val contentText = if (scheduled.isNotEmpty()) {
            val nextMs = scheduled.values.minOrNull() ?: 0L
            val nextTime = java.text.SimpleDateFormat("hh:mm a", java.util.Locale.getDefault()).format(java.util.Date(nextMs))
            "${scheduled.size} scheduled · Next deletion: $nextTime"
        } else {
            "No scheduled deletions"
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("ShotKeeper is monitoring screenshots")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setOngoing(true)
            .build()
    }

    private fun updateStatusNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildStatusNotification())
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "ShotKeeper detector", NotificationManager.IMPORTANCE_DEFAULT))
            manager.createNotificationChannel(NotificationChannel(ALERT_CHANNEL_ID, "Screenshot alerts", NotificationManager.IMPORTANCE_HIGH))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        observer?.let { contentResolver.unregisterContentObserver(it) }
        if (::workerThread.isInitialized) workerThread.quitSafely()
        super.onDestroy()
    }
}

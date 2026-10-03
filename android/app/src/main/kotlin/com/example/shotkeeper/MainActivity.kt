package com.example.shotkeeper

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "shotkeeper/permission"
    private var pendingNotificationPath: String? = null
    private var pendingNotificationName: String? = null
    private var channelInstance: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.getStringExtra("action")
        val path = intent?.getStringExtra("screenshot_path")
        val name = intent?.getStringExtra("screenshot_name")
        if (action == "schedule_screenshot" && path != null) {
            pendingNotificationPath = path
            pendingNotificationName = name ?: java.io.File(path).name
            channelInstance?.invokeMethod("on_notification_intent", mapOf(
                "path" to pendingNotificationPath,
                "name" to pendingNotificationName
            ))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channelInstance = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "get_sdk_int" -> result.success(android.os.Build.VERSION.SDK_INT)
                "manage_storage" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    })
                    result.success("opened")
                }
                "get_notification_intent" -> {
                    if (pendingNotificationPath != null) {
                        val map = mapOf(
                            "path" to pendingNotificationPath,
                            "name" to pendingNotificationName
                        )
                        pendingNotificationPath = null
                        pendingNotificationName = null
                        result.success(map)
                    } else {
                        result.success(null)
                    }
                }
                "start_detector" -> {
                    val intent = Intent(this, ScreenshotDetectorService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success("started")
                }
                "stop_detector" -> {
                    stopService(Intent(this, ScreenshotDetectorService::class.java))
                    result.success("stopped")
                }
                "increment_screenshot_count" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val current = prefs.getInt("flutter.shot_keeper_screenshot_count", 0)
                    val updated = current + 1
                    prefs.edit().putInt("flutter.shot_keeper_screenshot_count", updated).apply()
                    result.success(updated.toString())
                }
                "get_detected_screenshots" -> {
                    val list = mutableListOf<Map<String, String>>()
                    val projection = arrayOf(
                        android.provider.MediaStore.Images.Media._ID,
                        android.provider.MediaStore.Images.Media.DISPLAY_NAME,
                        android.provider.MediaStore.Images.Media.DATA,
                        android.provider.MediaStore.Images.Media.DATE_ADDED
                    )
                    val sortOrder = "${android.provider.MediaStore.Images.Media.DATE_ADDED} DESC, ${android.provider.MediaStore.Images.Media._ID} DESC"
                    contentResolver.query(
                        android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        projection,
                        null,
                        null,
                        sortOrder
                    )?.use { cursor ->
                        val nameCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DISPLAY_NAME)
                        val dataCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATA)
                        while (cursor.moveToNext()) {
                            val name = cursor.getString(nameCol) ?: continue
                            if (!name.contains("screenshot", true) && !name.contains("screen_shot", true) && !name.contains("screencap", true)) continue
                            val path = cursor.getString(dataCol) ?: continue
                            val file = java.io.File(path)
                            if (!file.exists()) continue
                            list.add(mapOf("path" to path, "name" to name))
                        }
                    }
                    result.success(list)
                }
                "get_count" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val count = prefs.getInt("flutter.shot_keeper_screenshot_count", 0)
                    result.success(count.toString())
                }
                "get_scheduled_deletions" -> {
                    val map = DeletionManager.getScheduledDeletions(this)
                    result.success(map.mapValues { it.value.toString() })
                }
                "schedule_deletion" -> {
                    val path = call.argument<String>("path")
                    val delaySeconds = (call.argument<Number>("delay_seconds"))?.toLong() ?: 0L
                    if (path != null) {
                        val targetMs = DeletionManager.scheduleDeletion(this, path, delaySeconds)
                        // Refresh notification with new schedule info
                        val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                        startForegroundService(serviceIntent)
                        result.success(targetMs.toString())
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "schedule_batch_deletion" -> {
                    val paths = call.argument<List<String>>("paths")
                    val delaySeconds = (call.argument<Number>("delay_seconds"))?.toLong() ?: 0L
                    if (paths != null) {
                        val targetMs = DeletionManager.scheduleBatchDeletion(this, paths, delaySeconds)
                        val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                        startForegroundService(serviceIntent)
                        result.success(targetMs.toString())
                    } else {
                        result.error("INVALID_ARGS", "Paths cannot be null", null)
                    }
                }
                "cancel_schedule" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        DeletionManager.cancelSchedule(this, path)
                        val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                        startForegroundService(serviceIntent)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "delete_now" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val deleted = DeletionManager.deleteFileNow(this, path)
                        val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                        startForegroundService(serviceIntent)
                        result.success(deleted)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "check_due_deletions" -> {
                    val count = DeletionManager.checkAndExecuteDueDeletions(this)
                    result.success(count)
                }
                else -> result.notImplemented()
            }
        }
    }
}

package com.example.shotkeeper

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.os.PowerManager
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
                    DeletionManager.setDetectorEnabled(this, true)
                    val intent = Intent(this, ScreenshotDetectorService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success("started")
                }
                "stop_detector" -> {
                    DeletionManager.setDetectorEnabled(this, false)
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
                "share_screenshot" -> {
                    val path = call.argument<String>("path")
                    val file = if (path != null) java.io.File(path) else null
                    if (file == null || !file.exists()) {
                        result.error("not_found", "Screenshot file not found", null)
                    } else {
                        try {
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this@MainActivity, "$packageName.fileprovider", file
                            )
                            val mime = if (file.name.endsWith(".png", true)) "image/png" else "image/jpeg"
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = mime
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(shareIntent, "Share screenshot"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
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
                        val dateCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATE_ADDED)
                        while (cursor.moveToNext()) {
                            val name = cursor.getString(nameCol) ?: continue
                            if (!name.contains("screenshot", true) && !name.contains("screen_shot", true) && !name.contains("screencap", true)) continue
                            val path = cursor.getString(dataCol) ?: continue
                            val file = java.io.File(path)
                            if (!file.exists()) continue
                            list.add(mapOf("path" to path, "name" to name, "date" to cursor.getLong(dateCol).toString()))
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
                        val moved = DeletionManager.moveToTrash(this, path)
                        val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                        startForegroundService(serviceIntent)
                        result.success(moved)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "delete_batch" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val failed = mutableListOf<String>()
                    var moved = 0
                    for (path in paths) {
                        if (DeletionManager.moveToTrash(this, path)) moved++ else failed.add(path)
                    }
                    val serviceIntent = Intent(this, ScreenshotDetectorService::class.java)
                    startForegroundService(serviceIntent)
                    result.success(mapOf("deleted" to moved, "failed" to failed))
                }
                "get_trash" -> {
                    DeletionManager.cleanExpiredTrash(this)
                    val trashMap = DeletionManager.getTrashMap(this)
                    val list = mutableListOf<Map<String, String>>()
                    val keyIter = trashMap.keys()
                    while (keyIter.hasNext()) {
                        val key = keyIter.next()
                        val meta = trashMap.optJSONObject(key)
                        if (meta != null) {
                            list.add(
                                mapOf(
                                    "path" to key,
                                    "trash" to meta.optString("t"),
                                    "name" to meta.optString("n"),
                                    "expiry" to meta.optLong("e").toString()
                                )
                            )
                        }
                    }
                    result.success(list)
                }
                "restore_from_trash" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val ok = DeletionManager.restoreFromTrash(this, path)
                        result.success(ok)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "empty_trash" -> result.success(DeletionManager.emptyTrash(this))
                "permanent_delete" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        result.success(DeletionManager.hardDeleteTrashItem(this, path))
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "set_pinned" -> {
                    val path = call.argument<String>("path")
                    val pinned = call.argument<Boolean>("pinned") ?: false
                    if (path != null) {
                        DeletionManager.setPinned(this, path, pinned)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "get_pinned" -> {
                    val pinned = mutableListOf<String>()
                    val pMap = org.json.JSONObject(
                        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                            .getString("flutter.shot_keeper_pinned", "{}") ?: "{}"
                    )
                    val keyIter = pMap.keys()
                    while (keyIter.hasNext()) pinned.add(keyIter.next())
                    result.success(pinned)
                }
                "check_due_deletions" -> {
                    val (deletedCount, failedPaths) = DeletionManager.checkAndExecuteDueDeletions(this)
                    if (failedPaths.isNotEmpty()) {
                        // Retried later; expose to Dart so the UI can inform the user
                        result.success(mapOf("deleted" to deletedCount, "failed" to failedPaths))
                    } else {
                        result.success(mapOf("deleted" to deletedCount, "failed" to emptyList<String>()))
                    }
                }
                "get_battery_optimization" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val ignoring = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        pm?.isIgnoringBatteryOptimizations(packageName) == true
                    } else {
                        true
                    }
                    result.success(ignoring)
                }
                "request_ignore_battery_optimization" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        if (pm != null &&
                            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M &&
                            !pm.isIgnoringBatteryOptimizations(packageName)
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    android.net.Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

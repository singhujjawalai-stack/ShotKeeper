package com.example.shotkeeper

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.Window
import android.widget.*
import java.io.File
import com.example.shotkeeper.R

class ScreenshotDialogActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.requestFeature(Window.FEATURE_NO_TITLE)
        setContentView(R.layout.screenshot_dialog)

        val path = intent.getStringExtra("screenshot_path") ?: ""
        val previewText = findViewById<TextView>(R.id.timelinePreview)
        val timelineBar = findViewById<ProgressBar>(R.id.timelineBar)
        val screenshotThumbnail = findViewById<ImageView>(R.id.screenshotThumbnail)

        if (path.isNotEmpty() && File(path).exists()) {
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                screenshotThumbnail.setImageBitmap(bitmap)
            } catch (e: Exception) {
                // Ignore
            }
        }

        // Preview default 4-hour schedule
        val defaultSeconds = 4L * 60 * 60
        val deleteTime = System.currentTimeMillis() + (defaultSeconds * 1000)
        val fmt = java.text.SimpleDateFormat("MMM d, yyyy 'at' h:mm a", java.util.Locale.getDefault())
        previewText.text = "Will delete by:\n${fmt.format(java.util.Date(deleteTime))}"
        timelineBar.progress = 30

        val displayName = intent.getStringExtra("screenshot_name") ?: File(path).name
        findViewById<TextView>(R.id.screenshotName).text = displayName

        val customBtn = findViewById<Button>(R.id.customOptionBtn)
        val customGroup = findViewById<LinearLayout>(R.id.customGroup)
        val customValue = findViewById<EditText>(R.id.customValue)
        val customUnit = findViewById<Spinner>(R.id.customUnit)
        val customScheduleBtn = findViewById<Button>(R.id.customScheduleBtn)

        val unitOptions = arrayOf("minutes", "hours", "days", "weeks", "months", "years")
        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, unitOptions)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        customUnit.adapter = adapter
        customUnit.setSelection(1) // hours

        customBtn.setOnClickListener {
            customGroup.visibility = android.view.View.VISIBLE
            customBtn.visibility = android.view.View.GONE
        }

        customScheduleBtn.setOnClickListener {
            val valueStr = customValue.text.toString()
            val value = valueStr.toIntOrNull() ?: 4
            val unit = customUnit.selectedItem?.toString() ?: "hours"
            val seconds = when (unit) {
                "minutes" -> value * 60L
                "hours" -> value * 3600L
                "days" -> value * 86400L
                "weeks" -> value * 7 * 86400L
                "months" -> value * 30 * 86400L
                "years" -> value * 365 * 86400L
                else -> value * 3600L
            }
            if (path.isNotEmpty()) {
                DeletionManager.scheduleDeletion(this, path, seconds)
            }
            finish()
        }

        findViewById<Button>(R.id.scheduleBtn).setOnClickListener {
            if (path.isNotEmpty()) {
                DeletionManager.scheduleDeletion(this, path, defaultSeconds)
            }
            finish()
        }
        findViewById<Button>(R.id.deleteNowBtn).setOnClickListener {
            if (path.isNotEmpty()) {
                DeletionManager.deleteFileNow(this, path)
            }
            finish()
        }
    }
}

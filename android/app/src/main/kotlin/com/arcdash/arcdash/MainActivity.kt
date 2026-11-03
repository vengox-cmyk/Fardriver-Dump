package com.arcdash.arcdash

import android.content.ContentValues
import android.content.Intent
import android.provider.MediaStore
import android.os.Build
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.arcdash.arcdash/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, ArcDashForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, ArcDashForegroundService::class.java))
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, publicChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        val sub = call.argument<String>("folder") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val mime = call.argument<String>("mime") ?: "text/plain"
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        Thread {
                            val ok = try {
                                savePublic(sub, name, mime, bytes)
                            } catch (e: Exception) {
                                false
                            }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private val publicChannel = "com.arcdash.arcdash/public_files"

    /**
     * Writes (or replaces) Documents/FarSure/<sub>/<name> through MediaStore.
     * Android 10+ only: no storage permission needed for files this app
     * creates. Older Android returns false (internal copy stays the source
     * of truth either way).
     */
    private fun savePublic(sub: String, name: String, mime: String, bytes: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        if (name.isEmpty() || name.contains('/') || sub.contains("..")) return false
        val resolver = contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relative = "Documents/FarSure/" + sub + "/"
        var uri = resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            MediaStore.MediaColumns.RELATIVE_PATH + "=? AND " +
                MediaStore.MediaColumns.DISPLAY_NAME + "=?",
            arrayOf(relative, name),
            null
        )?.use { c ->
            if (c.moveToFirst()) {
                android.content.ContentUris.withAppendedId(collection, c.getLong(0))
            } else null
        }
        if (uri == null) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            }
            uri = resolver.insert(collection, values) ?: return false
        }
        resolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: return false
        return true
    }
}

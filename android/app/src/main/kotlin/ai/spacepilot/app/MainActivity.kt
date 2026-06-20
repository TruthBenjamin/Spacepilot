package ai.spacepilot.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val scannerExecutor = Executors.newSingleThreadExecutor()
    private var scannerChannel: MethodChannel? = null
    private var pendingScanResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        scannerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_SCANNER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanStorage" -> beginScan(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingScanResult?.error("SCAN_CANCELLED", "Storage scan was cancelled", null)
        pendingScanResult = null
        scannerChannel?.setMethodCallHandler(null)
        scannerChannel = null
        scannerExecutor.shutdownNow()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun beginScan(result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            executeScan(result)
            return
        }

        pendingScanResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val appSettings = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            runCatching { startActivityForResult(appSettings, STORAGE_PERMISSION_REQUEST) }
                .onFailure {
                    startActivityForResult(
                        Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                        STORAGE_PERMISSION_REQUEST,
                    )
                }
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
        }
    }

    private fun executeScan(result: MethodChannel.Result) {
        scannerExecutor.execute {
            runCatching { scanStorage() }
                .onSuccess { files -> runOnUiThread { result.success(files) } }
                .onFailure { error ->
                    runOnUiThread {
                        result.error("SCAN_FAILED", error.message ?: "Storage scan failed", null)
                    }
                }
        }
    }

    @Deprecated("Android uses this callback for the storage settings activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == STORAGE_PERMISSION_REQUEST) completePermissionRequest()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQUEST) completePermissionRequest()
    }

    private fun completePermissionRequest() {
        val result = pendingScanResult ?: return
        pendingScanResult = null
        if (hasStoragePermission()) {
            executeScan(result)
        } else {
            result.error("PERMISSION_DENIED", "Storage access was not granted", null)
        }
    }

    private fun scanStorage(): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        SCANNED_FOLDERS.forEach { directoryType ->
            val root = Environment.getExternalStoragePublicDirectory(directoryType)
            val pending = ArrayDeque<File>().apply { add(root) }

            while (pending.isNotEmpty()) {
                val current = pending.removeLast()
                current.listFiles()?.forEach { entry ->
                    if (entry.isDirectory) {
                        pending.add(entry)
                    } else if (entry.isFile) {
                        files += mapOf(
                            "filename" to entry.name,
                            "path" to entry.absolutePath,
                            "size" to entry.length(),
                            "lastModified" to entry.lastModified(),
                        )
                    }
                }
            }
        }
        return files
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private companion object {
        const val STORAGE_SCANNER_CHANNEL = "ai.spacepilot.app/storage_scanner"
        const val STORAGE_PERMISSION_REQUEST = 4102
        val SCANNED_FOLDERS = listOf(
            Environment.DIRECTORY_DOWNLOADS,
            Environment.DIRECTORY_DCIM,
            Environment.DIRECTORY_MOVIES,
            Environment.DIRECTORY_PICTURES,
        )
    }
}

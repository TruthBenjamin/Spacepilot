package ai.spacepilot.app

import android.Manifest
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
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
    private var permissionChannel: MethodChannel? = null
    private var agentBackgroundChannel: MethodChannel? = null
    private var storageStatsChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionKind: PermissionKind? = null

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

        permissionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStorageAccess" -> result.success(hasStoragePermission())
                    "hasMediaAccess" -> result.success(hasMediaPermission())
                    "requestStorageAccess" -> requestStoragePermission(result)
                    "requestMediaAccess" -> requestMediaPermission(result)
                    else -> result.notImplemented()
                }
            }
        }

        agentBackgroundChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AGENT_BACKGROUND_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleMonitoring" -> result.success(scheduleAgentMonitoring())
                    "cancelMonitoring" -> result.success(cancelAgentMonitoring())
                    "loadSnapshots" -> result.success(StorageAgentSampler.loadSnapshots(this))
                    else -> result.notImplemented()
                }
            }
        }

        storageStatsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_STATS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageStats" -> result.success(StorageAgentSampler.currentSnapshot())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingPermissionResult?.error(
            "PERMISSION_CANCELLED",
            "Permission request was cancelled",
            null,
        )
        pendingPermissionResult = null
        pendingPermissionKind = null
        agentBackgroundChannel?.setMethodCallHandler(null)
        agentBackgroundChannel = null
        storageStatsChannel?.setMethodCallHandler(null)
        storageStatsChannel = null
        permissionChannel?.setMethodCallHandler(null)
        permissionChannel = null
        scannerChannel?.setMethodCallHandler(null)
        scannerChannel = null
        scannerExecutor.shutdownNow()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun beginScan(result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            executeScan(result)
        } else {
            result.error("PERMISSION_DENIED", "Storage access was not granted", null)
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
        if (requestCode == MEDIA_PERMISSION_REQUEST) completePermissionRequest()
    }

    private fun completePermissionRequest() {
        val result = pendingPermissionResult ?: return
        val kind = pendingPermissionKind ?: return
        pendingPermissionResult = null
        pendingPermissionKind = null

        when (kind) {
            PermissionKind.STORAGE -> result.success(hasStoragePermission())
            PermissionKind.MEDIA -> result.success(hasMediaPermission())
        }
    }

    private fun requestStoragePermission(result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            result.success(true)
            return
        }
        if (!startPermissionRequest(result, PermissionKind.STORAGE)) return

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

    private fun requestMediaPermission(result: MethodChannel.Result) {
        if (hasMediaPermission()) {
            result.success(true)
            return
        }
        if (!startPermissionRequest(result, PermissionKind.MEDIA)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_AUDIO,
                ),
                MEDIA_PERMISSION_REQUEST,
            )
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                MEDIA_PERMISSION_REQUEST,
            )
        }
    }

    private fun startPermissionRequest(
        result: MethodChannel.Result,
        kind: PermissionKind,
    ): Boolean {
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_IN_PROGRESS", "A permission request is already active", null)
            return false
        }

        pendingPermissionResult = result
        pendingPermissionKind = kind
        return true
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

    private fun hasMediaPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
            ).all { permission ->
                ContextCompat.checkSelfPermission(
                    this,
                    permission,
                ) == PackageManager.PERMISSION_GRANTED
            }
        } else {
            hasStoragePermission()
        }
    }

    private fun scheduleAgentMonitoring(): Boolean {
        return runCatching {
            StorageAgentSampler.capture(this)
            val scheduler = getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            val component = ComponentName(this, StorageAgentJobService::class.java)
            val job = JobInfo.Builder(AGENT_MONITORING_JOB_ID, component)
                .setPersisted(true)
                .setPeriodic(AGENT_MONITORING_INTERVAL_MS)
                .setRequiresBatteryNotLow(true)
                .build()

            scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
        }.getOrDefault(false)
    }

    private fun cancelAgentMonitoring(): Boolean {
        return runCatching {
            val scheduler = getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            scheduler.cancel(AGENT_MONITORING_JOB_ID)
            true
        }.getOrDefault(false)
    }

    private enum class PermissionKind {
        STORAGE,
        MEDIA,
    }

    private companion object {
        const val STORAGE_SCANNER_CHANNEL = "ai.spacepilot.app/storage_scanner"
        const val PERMISSIONS_CHANNEL = "ai.spacepilot.app/permissions"
        const val AGENT_BACKGROUND_CHANNEL = "ai.spacepilot.app/agent_background"
        const val STORAGE_STATS_CHANNEL = "ai.spacepilot.app/storage_stats"
        const val STORAGE_PERMISSION_REQUEST = 4102
        const val MEDIA_PERMISSION_REQUEST = 4103
        const val AGENT_MONITORING_JOB_ID = 4201
        const val AGENT_MONITORING_INTERVAL_MS = 60L * 60L * 1000L
        val SCANNED_FOLDERS = listOf(
            Environment.DIRECTORY_DOWNLOADS,
            Environment.DIRECTORY_DCIM,
            Environment.DIRECTORY_MOVIES,
            Environment.DIRECTORY_PICTURES,
        )
    }
}

package ai.spacepilot.app

import android.Manifest
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.StorageStatsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.BatteryManager
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val scannerExecutor = Executors.newSingleThreadExecutor()
    private val cancelStorageScan = AtomicBoolean(false)
    private var scannerChannel: MethodChannel? = null
    private var permissionChannel: MethodChannel? = null
    private var agentBackgroundChannel: MethodChannel? = null
    private var storageStatsChannel: MethodChannel? = null
    private var appPreferencesChannel: MethodChannel? = null
    private var fileActionChannel: MethodChannel? = null
    private var appAnalyzerChannel: MethodChannel? = null
    private var powerThermalChannel: MethodChannel? = null
    private var ramBoosterChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionKind: PermissionKind? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        scannerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_SCANNER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanStorage" -> beginLegacyScan(result)
                    "scanStorageIntelligence" -> beginScan(
                        result,
                        call.argument<Boolean>("includeHidden") == true,
                    )
                    "cancelStorageScan" -> {
                        cancelStorageScan.set(true)
                        result.success(null)
                    }
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_INFO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success("${info.versionName ?: "0.0.0"}+${info.longVersionCode}")
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_WORK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureRecoveryPurge" -> BackgroundWorkCoordinator.ensureRecoveryPurge(this)
                "syncRecoveryPurge" -> BackgroundWorkCoordinator.syncRecoveryPurge(
                    this,
                    call.argument<Boolean>("enabled") == true,
                )
                "syncRule" -> BackgroundWorkCoordinator.syncRule(
                    this,
                    call.argument<Map<*, *>>("rule") ?: emptyMap<String, Any>(),
                )
                "syncScheduledScan" -> BackgroundWorkCoordinator.syncScheduledScan(
                    this,
                    call.argument<Boolean>("enabled") == true,
                    (call.argument<Number>("frequencyDays")?.toLong() ?: 1L),
                    (call.argument<Number>("initialDelayMs")?.toLong() ?: 0L),
                )
                "cancel" -> call.argument<String>("workName")?.let {
                    BackgroundWorkCoordinator.cancel(this, it)
                }
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            result.success(null)
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

        appPreferencesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_PREFERENCES_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasCompletedOnboarding" -> {
                        result.success(
                            appPreferences().getBoolean(ONBOARDING_COMPLETED_KEY, false),
                        )
                    }
                    "setOnboardingCompleted" -> {
                        appPreferences()
                            .edit()
                            .putBoolean(ONBOARDING_COMPLETED_KEY, true)
                            .apply()
                        result.success(null)
                    }
                    "getString" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrBlank()) {
                            result.error("INVALID_KEY", "Preference key was not provided", null)
                        } else {
                            result.success(appPreferences().getString(key, null))
                        }
                    }
                    "setString" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key.isNullOrBlank()) {
                            result.error("INVALID_KEY", "Preference key was not provided", null)
                        } else {
                            appPreferences().edit().putString(key, value ?: "").apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        fileActionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_ACTIONS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openFile" -> openFile(call.argument("path"), result)
                    "shareFile" -> shareFile(call.argument("path"), result)
                    "moveFile" -> moveFile(
                        call.argument("path"),
                        call.argument("destination"),
                        result,
                    )
                    "renameFile" -> renameFile(
                        call.argument("path"),
                        call.argument("filename"),
                        result,
                    )
                    "moveToRecovery" -> moveToRecovery(
                        call.argument("path"),
                        call.argument("retentionDays"),
                        result,
                    )
                    "restoreRecoveryItem" -> restoreRecoveryItem(
                        call.argument("recoveryPath"),
                        call.argument("originalPath"),
                        result,
                    )
                    "deleteRecoveryItem" -> deleteRecoveryItem(
                        call.argument("recoveryPath"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        }

        appAnalyzerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_ANALYZER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyzeInstalledApps" -> analyzeInstalledApps(result)
                    "hasUsageAccess" -> result.success(hasUsageStatsAccess())
                    "openUsageAccessSettings" -> openUsageAccessSettings(result)
                    "openApp" -> openApp(call.argument("packageName"), result)
                    "openAppInfo" -> openAppInfo(call.argument("packageName"), result)
                    "requestUninstall" -> requestUninstall(
                        call.argument("packageName"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        }

        powerThermalChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POWER_THERMAL_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPowerThermalSnapshot" -> result.success(powerThermalSnapshot())
                    "openBatterySaverSettings" -> openSystemSettings(
                        Settings.ACTION_BATTERY_SAVER_SETTINGS,
                        result,
                    )
                    "openBatteryUsageSettings" -> openSystemSettings(
                        Intent.ACTION_POWER_USAGE_SUMMARY,
                        result,
                    )
                    "openDisplaySettings" -> openSystemSettings(
                        Settings.ACTION_DISPLAY_SETTINGS,
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        }

        ramBoosterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RAM_BOOSTER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMemorySnapshot" -> result.success(memorySnapshot())
                    "boostRam" -> boostRam(result)
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
        appPreferencesChannel?.setMethodCallHandler(null)
        appPreferencesChannel = null
        fileActionChannel?.setMethodCallHandler(null)
        fileActionChannel = null
        appAnalyzerChannel?.setMethodCallHandler(null)
        appAnalyzerChannel = null
        powerThermalChannel?.setMethodCallHandler(null)
        powerThermalChannel = null
        ramBoosterChannel?.setMethodCallHandler(null)
        ramBoosterChannel = null
        permissionChannel?.setMethodCallHandler(null)
        permissionChannel = null
        scannerChannel?.setMethodCallHandler(null)
        scannerChannel = null
        scannerExecutor.shutdownNow()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun powerThermalSnapshot(): Map<String, Any?> {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val temperatureTenths = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val health = battery?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager

        return mapOf(
            "capturedAt" to System.currentTimeMillis(),
            "batteryLevel" to if (level >= 0 && scale > 0) (level * 100 / scale) else null,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL),
            "plugged" to (plugged != 0),
            "powerSource" to when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                else -> if (plugged == 0) "battery" else "unknown"
            },
            "powerSaveMode" to powerManager.isPowerSaveMode,
            "batteryTemperatureCelsius" to if (temperatureTenths >= 0) {
                temperatureTenths / 10.0
            } else null,
            "batteryHealth" to batteryHealthName(health),
            "thermalStatus" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                powerManager.currentThermalStatus
            } else null,
            "thermalStatusSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
        )
    }

    private fun batteryHealthName(health: Int): String? = when (health) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "overVoltage"
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        else -> null
    }

    private fun openSystemSettings(action: String, result: MethodChannel.Result) {
        runCatching { startActivity(Intent(action)) }
            .onSuccess { result.success(null) }
            .onFailure { result.error("SETTINGS_UNAVAILABLE", "System settings are unavailable", null) }
    }

    private fun beginScan(result: MethodChannel.Result, includeHidden: Boolean) {
        if (hasStoragePermission()) {
            executeScan(result, includeHidden)
        } else {
            result.error("PERMISSION_DENIED", "Storage access was not granted", null)
        }
    }

    private fun beginLegacyScan(result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            executeLegacyScan(result)
        } else {
            result.error("PERMISSION_DENIED", "Storage access was not granted", null)
        }
    }

    private fun executeScan(result: MethodChannel.Result, includeHidden: Boolean) {
        cancelStorageScan.set(false)
        scannerExecutor.execute {
            runCatching { scanStorageIntelligence(includeHidden) }
                .onSuccess { report -> runOnUiThread { result.success(report) } }
                .onFailure { error ->
                    runOnUiThread {
                        result.error("SCAN_FAILED", error.message ?: "Storage scan failed", null)
                    }
                }
        }
    }

    private fun executeLegacyScan(result: MethodChannel.Result) {
        cancelStorageScan.set(false)
        scannerExecutor.execute {
            runCatching { scanStorageIntelligence()["files"] ?: emptyList<Map<String, Any>>() }
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
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            pendingNotificationResult?.success(hasNotificationPermission())
            pendingNotificationResult = null
        }
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            hasPermission(Manifest.permission.POST_NOTIFICATIONS)

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (pendingNotificationResult != null) {
            result.error("REQUEST_IN_PROGRESS", "A notification permission request is already active", null)
            return
        }
        pendingNotificationResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
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

        requestPermissions(mediaReadPermissions(), MEDIA_PERMISSION_REQUEST)
    }

    private fun openFile(path: String?, result: MethodChannel.Result) {
        val file = validatedFile(path)
        if (file == null) {
            result.error("FILE_NOT_FOUND", "File was not found", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(fileUri(file), mimeType(file))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure {
                result.error("NO_HANDLER", "No app can open this file", null)
            }
    }

    private fun shareFile(path: String?, result: MethodChannel.Result) {
        val file = validatedFile(path)
        if (file == null) {
            result.error("FILE_NOT_FOUND", "File was not found", null)
            return
        }

        val uri = fileUri(file)
        val intent = Intent(Intent.ACTION_SEND)
            .setType(mimeType(file))
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        runCatching { startActivity(Intent.createChooser(intent, "Share file")) }
            .onSuccess { result.success(null) }
            .onFailure {
                result.error("NO_HANDLER", "No app can share this file", null)
            }
    }

    private fun moveFile(
        path: String?,
        destination: String?,
        result: MethodChannel.Result,
    ) {
        val source = validatedFile(path)
        if (source == null) {
            result.error("FILE_NOT_FOUND", "File was not found", null)
            return
        }
        val destinationRoot = destinationRoot(destination)
        if (destinationRoot == null) {
            result.error("MOVE_FAILED", "Destination is not supported", null)
            return
        }

        scannerExecutor.execute {
            runCatching {
                destinationRoot.mkdirs()
                if (!destinationRoot.isDirectory) {
                    error("Destination folder is unavailable")
                }

                val target = availableDestinationFile(destinationRoot, source.name)
                val moved = source.renameTo(target)
                if (!moved) {
                    source.copyTo(target, overwrite = false)
                    if (!source.delete()) {
                        target.delete()
                        error("Original file could not be removed")
                    }
                }

                mapOf(
                    "path" to target.absolutePath,
                    "filename" to target.name,
                )
            }.onSuccess { payload ->
                runOnUiThread { result.success(payload) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error("MOVE_FAILED", error.message ?: "File could not be moved", null)
                }
            }
        }
    }

    private fun renameFile(
        path: String?,
        filename: String?,
        result: MethodChannel.Result,
    ) {
        val source = validatedFile(path)
        if (source == null) {
            result.error("FILE_NOT_FOUND", "File was not found", null)
            return
        }
        if (!isValidFilename(filename)) {
            result.error("INVALID_NAME", "Filename is invalid", null)
            return
        }

        scannerExecutor.execute {
            runCatching {
                val target = File(source.parentFile, filename!!)
                if (target.exists()) {
                    error("A file with that name already exists")
                }
                moveOrCopyDelete(source, target)
                mapOf(
                    "path" to target.absolutePath,
                    "filename" to target.name,
                )
            }.onSuccess { payload ->
                runOnUiThread { result.success(payload) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error("RENAME_FAILED", error.message ?: "File could not be renamed", null)
                }
            }
        }
    }

    private fun moveToRecovery(
        path: String?,
        retentionDays: Int?,
        result: MethodChannel.Result,
    ) {
        val source = validatedFile(path)
        if (source == null) {
            result.error("FILE_NOT_FOUND", "File was not found", null)
            return
        }

        scannerExecutor.execute {
            runCatching {
                val root = recoveryRoot()
                root.mkdirs()
                if (!root.isDirectory) {
                    error("Recovery storage is unavailable")
                }

                val now = System.currentTimeMillis()
                val days = (retentionDays ?: 30).coerceIn(7, 90)
                val id = "${now}_${UUID.randomUUID()}"
                val target = availableDestinationFile(root, "${id}_${source.name}")
                val sizeBytes = source.length().coerceAtLeast(0L)
                val originalPath = source.absolutePath
                moveOrCopyDelete(source, target)

                mapOf(
                    "id" to id,
                    "filename" to source.name,
                    "originalPath" to originalPath,
                    "recoveryPath" to target.absolutePath,
                    "sizeBytes" to sizeBytes,
                    "deletedAt" to now,
                    "expiresAt" to now + days * MILLIS_PER_DAY,
                )
            }.onSuccess { payload ->
                runOnUiThread { result.success(payload) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "RECOVERY_FAILED",
                        error.message ?: "File could not be moved to Recovery Bin",
                        null,
                    )
                }
            }
        }
    }

    private fun restoreRecoveryItem(
        recoveryPath: String?,
        originalPath: String?,
        result: MethodChannel.Result,
    ) {
        val source = validatedRecoveryFile(recoveryPath)
        if (source == null || originalPath.isNullOrBlank()) {
            result.error("FILE_NOT_FOUND", "Recovery item was not found", null)
            return
        }

        scannerExecutor.execute {
            runCatching {
                val requested = File(originalPath)
                val destinationRoot = requested.parentFile ?: error("Original folder is unavailable")
                destinationRoot.mkdirs()
                if (!destinationRoot.isDirectory) {
                    error("Original folder is unavailable")
                }

                val target = availableDestinationFile(destinationRoot, requested.name)
                moveOrCopyDelete(source, target)
                mapOf(
                    "path" to target.absolutePath,
                    "filename" to target.name,
                )
            }.onSuccess { payload ->
                runOnUiThread { result.success(payload) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error("RESTORE_FAILED", error.message ?: "File could not be restored", null)
                }
            }
        }
    }

    private fun deleteRecoveryItem(
        recoveryPath: String?,
        result: MethodChannel.Result,
    ) {
        val file = validatedRecoveryFile(recoveryPath)
        if (file == null) {
            result.error("FILE_NOT_FOUND", "Recovery item was not found", null)
            return
        }

        scannerExecutor.execute {
            runCatching {
                if (!file.delete()) {
                    error("Recovery item could not be deleted")
                }
            }.onSuccess {
                runOnUiThread { result.success(null) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error("DELETE_FAILED", error.message ?: "Recovery item could not be deleted", null)
                }
            }
        }
    }

    private fun analyzeInstalledApps(result: MethodChannel.Result) {
        scannerExecutor.execute {
            runCatching { installedAppsReport() }
                .onSuccess { report -> runOnUiThread { result.success(report) } }
                .onFailure { error ->
                    runOnUiThread {
                        result.error(
                            "APP_ANALYSIS_FAILED",
                            error.message ?: "Installed app analysis failed",
                            null,
                        )
                    }
                }
        }
    }

    private fun boostRam(result: MethodChannel.Result) {
        scannerExecutor.execute {
            runCatching { ramBoostReport() }
                .onSuccess { report -> runOnUiThread { result.success(report) } }
                .onFailure { error ->
                    runOnUiThread {
                        result.error(
                            "RAM_BOOST_FAILED",
                            error.message ?: "RAM boost failed",
                            null,
                        )
                    }
                }
        }
    }

    private fun ramBoostReport(): Map<String, Any> {
        val before = memorySnapshot()
        val optimizedPackages = mutableListOf<String>()
        val skippedPackages = mutableListOf<String>()

        onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        System.gc()

        candidatePackagesForRamBoost().forEach { candidate ->
            if (candidate == packageName) {
                skippedPackages += candidate
                return@forEach
            }
            runCatching {
                val appInfo = packageManager.getApplicationInfo(candidate, 0)
                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                if (isSystemApp) {
                    skippedPackages += candidate
                } else {
                    val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    manager.killBackgroundProcesses(candidate)
                    optimizedPackages += candidate
                }
            }.onFailure {
                skippedPackages += candidate
            }
        }

        Thread.sleep(350L)
        val after = memorySnapshot()
        return mapOf(
            "before" to before,
            "after" to after,
            "optimizedAppCount" to optimizedPackages.size,
            "optimizedPackages" to optimizedPackages,
            "skippedPackages" to skippedPackages,
            "limitations" to listOf(
                "Android may restart needed apps and does not allow third-party apps to force-stop protected processes.",
            ),
        )
    }

    private fun memorySnapshot(): Map<String, Any> {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return mapOf(
            "totalBytes" to info.totalMem.coerceAtLeast(0L),
            "availableBytes" to info.availMem.coerceAtLeast(0L),
            "lowMemory" to info.lowMemory,
            "thresholdBytes" to info.threshold.coerceAtLeast(0L),
            "capturedAt" to System.currentTimeMillis(),
        )
    }

    private fun candidatePackagesForRamBoost(): Set<String> {
        val launchIntent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
        val launchablePackages = packageManager
            .queryIntentActivities(launchIntent, 0)
            .map { it.activityInfo.packageName }
            .filter { it != packageName }
            .toSet()

        if (!hasUsageStatsAccess()) return launchablePackages.take(MAX_RAM_BOOST_PACKAGES).toSet()

        val now = System.currentTimeMillis()
        val recentCutoff = now - RAM_BOOST_RECENT_APP_WINDOW_MS
        val usageByPackage = usageStatsByPackage()
        return launchablePackages
            .sortedWith(
                compareByDescending<String> { usageByPackage[it]?.lastTimeUsed ?: 0L },
            )
            .filter { packageName ->
                val usage = usageByPackage[packageName]
                usage == null || usage.lastTimeUsed < recentCutoff
            }
            .take(MAX_RAM_BOOST_PACKAGES)
            .toSet()
    }

    private fun installedAppsReport(): Map<String, Any> {
        val usageAccess = hasUsageStatsAccess()
        val usageByPackage = if (usageAccess) usageStatsByPackage() else emptyMap()
        val launchIntent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
        val launchablePackages = packageManager
            .queryIntentActivities(launchIntent, 0)
            .map { it.activityInfo.packageName }
            .toSet()

        val apps = launchablePackages.mapNotNull { packageName ->
            runCatching {
                val packageInfo = packageManager.getPackageInfo(packageName, 0)
                val appInfo = packageInfo.applicationInfo ?: return@runCatching null
                val usage = usageByPackage[packageName]
                val storage = appStorageFor(packageName, appInfo)
                mapOf(
                    "packageName" to packageName,
                    "appName" to appInfo.loadLabel(packageManager).toString(),
                    "versionName" to (packageInfo.versionName ?: ""),
                    "versionCode" to packageInfo.longVersionCode,
                    "firstInstallTime" to packageInfo.firstInstallTime,
                    "lastUpdateTime" to packageInfo.lastUpdateTime,
                    "isSystemApp" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    "canLaunch" to (packageManager.getLaunchIntentForPackage(packageName) != null),
                    "hasUsageAccess" to usageAccess,
                    "appSizeBytes" to storage.appBytes,
                    "dataSizeBytes" to storage.dataBytes,
                    "cacheSizeBytes" to storage.cacheBytes,
                    "totalSizeBytes" to storage.totalBytes,
                    "lastUsedTime" to (usage?.lastTimeUsed ?: 0L),
                    "usageTimeMillis" to (usage?.totalTimeInForeground ?: 0L),
                )
            }.getOrNull()
        }.filterNotNull()
            .sortedWith(compareBy<Map<String, Any>> { (it["appName"] as String).lowercase() })

        val limitations = mutableListOf(
            "Android package visibility limits this list to apps SpacePilot can legitimately query.",
            "Cache clearing and force-stop controls are not exposed because Android reserves them for system apps.",
        )
        if (!usageAccess) {
            limitations += "Grant Usage Access to show last-used times and more complete app storage where Android supports it."
        }

        return mapOf(
            "apps" to apps,
            "hasUsageAccess" to usageAccess,
            "generatedAt" to System.currentTimeMillis(),
            "limitations" to limitations,
        )
    }

    private fun usageStatsByPackage(): Map<String, UsageStats> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - APP_USAGE_WINDOW_MS
        return manager.queryAndAggregateUsageStats(start, end)
    }

    private fun appStorageFor(packageName: String, appInfo: ApplicationInfo): AppStorageSnapshot {
        val apkBytes = runCatching { File(appInfo.sourceDir).length().coerceAtLeast(0L) }
            .getOrDefault(0L)

        if (!hasUsageStatsAccess()) {
            return AppStorageSnapshot(appBytes = apkBytes)
        }

        return try {
            val manager = getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
            val stats = manager.queryStatsForPackage(
                android.os.storage.StorageManager.UUID_DEFAULT,
                packageName,
                Process.myUserHandle(),
            )
            AppStorageSnapshot(
                appBytes = stats.appBytes.coerceAtLeast(apkBytes),
                dataBytes = stats.dataBytes.coerceAtLeast(0L),
                cacheBytes = stats.cacheBytes.coerceAtLeast(0L),
            )
        } catch (_: SecurityException) {
            AppStorageSnapshot(appBytes = apkBytes)
        } catch (_: IOException) {
            AppStorageSnapshot(appBytes = apkBytes)
        } catch (_: RuntimeException) {
            AppStorageSnapshot(appBytes = apkBytes)
        }
    }

    private fun hasUsageStatsAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings(result: MethodChannel.Result) {
        runCatching {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }.onSuccess {
            result.success(null)
        }.onFailure {
            result.error("NO_HANDLER", "Usage Access settings could not be opened", null)
        }
    }

    private fun openApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("APP_NOT_FOUND", "App package was not provided", null)
            return
        }
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent == null) {
            result.error("APP_NOT_FOUND", "App cannot be opened", null)
            return
        }
        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure { result.error("NO_HANDLER", "App could not be opened", null) }
    }

    private fun openAppInfo(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("APP_NOT_FOUND", "App package was not provided", null)
            return
        }
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure { result.error("NO_HANDLER", "App info could not be opened", null) }
    }

    private fun requestUninstall(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("APP_NOT_FOUND", "App package was not provided", null)
            return
        }
        val intent = Intent(Intent.ACTION_DELETE)
            .setData(Uri.parse("package:$packageName"))
        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure { result.error("NO_HANDLER", "Uninstall flow could not be opened", null) }
    }

    private fun validatedFile(path: String?): File? {
        if (path.isNullOrBlank()) return null

        val file = runCatching { File(path).canonicalFile }.getOrNull() ?: return null
        if (!file.isFile) return null
        return file
    }

    private fun validatedRecoveryFile(path: String?): File? {
        if (path.isNullOrBlank()) return null

        val file = runCatching { File(path).canonicalFile }.getOrNull() ?: return null
        val root = runCatching { recoveryRoot().canonicalFile }.getOrNull() ?: return null
        if (!file.isFile || !isInside(file, root)) return null
        return file
    }

    private fun isValidFilename(filename: String?): Boolean {
        if (filename.isNullOrBlank()) return false
        if (filename == "." || filename == "..") return false
        return !filename.contains("/") && !filename.contains("\\")
    }

    private fun recoveryRoot(): File {
        return File(getExternalFilesDir(null) ?: filesDir, "recovery_bin")
    }

    private fun moveOrCopyDelete(source: File, target: File) {
        target.parentFile?.mkdirs()
        val moved = source.renameTo(target)
        if (!moved) {
            source.copyTo(target, overwrite = false)
            if (!source.delete()) {
                target.delete()
                error("Original file could not be removed")
            }
        }
    }

    private fun fileUri(file: File): Uri {
        return FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
    }

    private fun mimeType(file: File): String {
        val extension = file.extension.lowercase()
        if (extension.isBlank()) return "application/octet-stream"

        return android.webkit.MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private fun destinationRoot(destination: String?): File? {
        val directoryType = when (destination) {
            "downloads" -> Environment.DIRECTORY_DOWNLOADS
            "dcim" -> Environment.DIRECTORY_DCIM
            "movies" -> Environment.DIRECTORY_MOVIES
            "pictures" -> Environment.DIRECTORY_PICTURES
            else -> return null
        }

        return runCatching {
            Environment.getExternalStoragePublicDirectory(directoryType).canonicalFile
        }.getOrNull()
    }

    private fun availableDestinationFile(root: File, filename: String): File {
        val initial = File(root, filename)
        if (!initial.exists()) return initial

        val dotIndex = filename.lastIndexOf('.')
        val base = if (dotIndex > 0) filename.substring(0, dotIndex) else filename
        val extension = if (dotIndex > 0) filename.substring(dotIndex) else ""

        var index = 1
        while (true) {
            val candidate = File(root, "$base ($index)$extension")
            if (!candidate.exists()) return candidate
            index += 1
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

    private fun scanStorageIntelligence(includeHidden: Boolean = false): Map<String, Any> {
        val startedAt = System.currentTimeMillis()
        val files = mutableListOf<Map<String, Any>>()
        val folderAccumulators = mutableMapOf<String, FolderAccumulator>()
        val categoryAccumulators = mutableMapOf<String, CategoryAccumulator>()
        val emptyFolders = mutableListOf<Map<String, Any>>()
        val scannedRootPaths = mutableListOf<String>()

        val roots = SCANNED_FOLDERS.mapNotNull { directoryType ->
            runCatching { Environment.getExternalStoragePublicDirectory(directoryType).canonicalFile }
                .getOrNull()
        }.distinctBy { it.absolutePath }

        roots.forEachIndexed { rootIndex, root ->
            if (cancelStorageScan.get()) return@forEachIndexed
            reportStorageScanProgress(
                fraction = 0.05 + (rootIndex.toDouble() / roots.size.coerceAtLeast(1)) * 0.9,
                filesAnalyzed = files.size,
                bytesAnalyzed = files.sumOf { (it["size"] as? Long) ?: 0L },
                scannedRootCount = scannedRootPaths.size,
            )
            if (!root.exists() || !root.isDirectory) return@forEachIndexed

            scannedRootPaths += root.absolutePath
            val pending = ArrayDeque<File>().apply { add(root) }

            while (pending.isNotEmpty() && !cancelStorageScan.get()) {
                val current = pending.removeLast()
                val entries = current.listFiles()
                if (entries != null && entries.isEmpty()) {
                    emptyFolders += mapOf(
                        "path" to current.absolutePath,
                        "lastModified" to current.lastModified(),
                    )
                }
                entries?.forEach { entry ->
                    if (cancelStorageScan.get()) return@forEach
                    if (!includeHidden && entry.name.startsWith(".")) return@forEach
                    if (Files.isSymbolicLink(entry.toPath())) return@forEach

                    val canonicalEntry = runCatching { entry.canonicalFile }.getOrNull()
                        ?: return@forEach
                    if (!isInside(canonicalEntry, root)) return@forEach

                    if (canonicalEntry.isDirectory) {
                        pending.add(canonicalEntry)
                    } else if (canonicalEntry.isFile) {
                        val sizeBytes = canonicalEntry.length().coerceAtLeast(0L)
                        val lastModified = canonicalEntry.lastModified()
                        val categories = categoriesFor(canonicalEntry)
                        val previewType = previewTypeFor(categories)
                        val previewPath = if (previewType != null) {
                            canonicalEntry.absolutePath
                        } else {
                            null
                        }
                        val file = mutableMapOf<String, Any>(
                            "filename" to canonicalEntry.name,
                            "path" to canonicalEntry.absolutePath,
                            "size" to sizeBytes,
                            "lastModified" to lastModified,
                            "categories" to categories,
                        )
                        if (previewPath != null && previewType != null) {
                            file["previewPath"] = previewPath
                            file["previewType"] = previewType
                        }
                        files += file
                        addFileToFolders(
                            canonicalEntry.parentFile,
                            root,
                            sizeBytes,
                            lastModified,
                            folderAccumulators,
                        )
                        categories.forEach { category ->
                            val accumulator = categoryAccumulators.getOrPut(category) {
                                CategoryAccumulator()
                            }
                            accumulator.fileCount += 1
                            accumulator.totalBytes += sizeBytes
                        }
                    }
                }
            }
            reportStorageScanProgress(
                fraction = 0.05 + ((rootIndex + 1).toDouble() / roots.size.coerceAtLeast(1)) * 0.9,
                filesAnalyzed = files.size,
                bytesAnalyzed = files.sumOf { (it["size"] as? Long) ?: 0L },
                scannedRootCount = scannedRootPaths.size,
            )
        }

        val largestFolders = folderAccumulators.entries
            .sortedByDescending { it.value.sizeBytes }
            .take(MAX_REPORTED_FOLDERS)
            .map { (path, accumulator) ->
                mapOf(
                    "path" to path,
                    "sizeBytes" to accumulator.sizeBytes,
                    "fileCount" to accumulator.fileCount,
                    "lastModified" to accumulator.lastModified,
                )
            }
        val summaries = STORAGE_CATEGORIES.map { category ->
            val accumulator = categoryAccumulators[category] ?: CategoryAccumulator()
            mapOf(
                "category" to category,
                "fileCount" to accumulator.fileCount,
                "totalBytes" to accumulator.totalBytes,
            )
        }

        return mapOf(
            "storageStats" to storageStatsSnapshot(startedAt),
            "files" to files,
            "largestFolders" to largestFolders,
            "emptyFolders" to emptyFolders,
            "categorySummaries" to summaries,
            "scannedRootPaths" to scannedRootPaths.distinct(),
            "completedAt" to System.currentTimeMillis(),
            "cancelled" to cancelStorageScan.get(),
        )
    }

    private fun reportStorageScanProgress(
        fraction: Double,
        filesAnalyzed: Int,
        bytesAnalyzed: Long,
        scannedRootCount: Int,
    ) {
        runOnUiThread {
            scannerChannel?.invokeMethod(
                "storageScanProgress",
                mapOf(
                    "fraction" to fraction.coerceIn(0.0, 1.0),
                    "filesAnalyzed" to filesAnalyzed,
                    "bytesAnalyzed" to bytesAnalyzed,
                    "scannedRootCount" to scannedRootCount,
                ),
            )
        }
    }

    private fun scanStorage(): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        SCANNED_FOLDERS.forEach { directoryType ->
            val root = Environment.getExternalStoragePublicDirectory(directoryType)
            val canonicalRoot = root.canonicalFile
            val pending = ArrayDeque<File>().apply { add(root) }

            while (pending.isNotEmpty()) {
                val current = pending.removeLast()
                current.listFiles()?.forEach { entry ->
                    if (Files.isSymbolicLink(entry.toPath())) return@forEach

                    val canonicalEntry = runCatching { entry.canonicalFile }.getOrNull()
                        ?: return@forEach
                    if (!isInside(canonicalEntry, canonicalRoot)) return@forEach

                    if (canonicalEntry.isDirectory) {
                        pending.add(canonicalEntry)
                    } else if (canonicalEntry.isFile) {
                        files += mapOf(
                            "filename" to canonicalEntry.name,
                            "path" to canonicalEntry.absolutePath,
                            "size" to canonicalEntry.length(),
                            "lastModified" to canonicalEntry.lastModified(),
                        )
                    }
                }
            }
        }
        return files
    }

    private fun scanRoots(): List<File> {
        val roots = mutableListOf<File>()
        roots += Environment.getExternalStorageDirectory()
        externalMediaDirs.filterNotNull().forEach { roots += mediaStorageRoot(it) }

        val canonicalRoots = roots
            .mapNotNull { root -> runCatching { root.canonicalFile }.getOrNull() }
            .distinctBy { it.absolutePath }

        return canonicalRoots.filter { candidate ->
            canonicalRoots.none { other ->
                other.absolutePath != candidate.absolutePath && isInside(candidate, other)
            }
        }
    }

    private fun mediaStorageRoot(mediaDirectory: File): File {
        var current: File? = mediaDirectory
        while (current != null && current.name != "Android") {
            current = current.parentFile
        }

        return current?.parentFile ?: mediaDirectory
    }

    private fun addFileToFolders(
        parent: File?,
        root: File,
        sizeBytes: Long,
        lastModified: Long,
        accumulators: MutableMap<String, FolderAccumulator>,
    ) {
        var current = parent
        while (current != null && isInside(current, root) && current.absolutePath != root.absolutePath) {
            val accumulator = accumulators.getOrPut(current.absolutePath) { FolderAccumulator() }
            accumulator.sizeBytes += sizeBytes
            accumulator.fileCount += 1
            if (lastModified > accumulator.lastModified) {
                accumulator.lastModified = lastModified
            }
            current = current.parentFile
        }
    }

    private fun storageStatsSnapshot(capturedAt: Long): Map<String, Any> {
        val root = Environment.getExternalStorageDirectory()
        val totalBytes = root.totalSpace.coerceAtLeast(0L)
        val freeBytes = root.freeSpace.coerceIn(0L, totalBytes)
        val usedBytes = (totalBytes - freeBytes).coerceAtLeast(0L)

        return mapOf(
            "totalBytes" to totalBytes,
            "usedBytes" to usedBytes,
            "freeBytes" to freeBytes,
            "capturedAt" to capturedAt,
        )
    }

    private fun categoriesFor(file: File): List<String> {
        val extension = file.extension.lowercase()
        val normalizedPath = file.absolutePath.replace(File.separatorChar, '/').lowercase()
        val categories = mutableListOf<String>()

        if (extension in IMAGE_EXTENSIONS) categories += "image"
        if (extension in VIDEO_EXTENSIONS) categories += "video"
        if (extension in AUDIO_EXTENSIONS) categories += "audio"
        if (extension in DOCUMENT_EXTENSIONS) categories += "document"
        if (extension == "apk") categories += "apk"
        if (extension in ZIP_EXTENSIONS) categories += "zip"
        if (normalizedPath.contains("/download/")) categories += "download"
        if (categories.isEmpty()) categories += "other"

        return categories
    }

    private fun previewTypeFor(categories: List<String>): String? {
        return when {
            "image" in categories -> "image"
            "video" in categories -> "video"
            else -> null
        }
    }

    private fun isInside(entry: File, root: File): Boolean {
        val rootPath = root.path.trimEnd(File.separatorChar)
        return entry.path == rootPath || entry.path.startsWith("$rootPath${File.separator}")
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
        if (hasStoragePermission()) return true

        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                val hasFullVisualAccess = hasPermission(Manifest.permission.READ_MEDIA_IMAGES) &&
                    hasPermission(Manifest.permission.READ_MEDIA_VIDEO)
                val hasSelectedVisualAccess = hasPermission(
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                )
                val hasAudioAccess = hasPermission(Manifest.permission.READ_MEDIA_AUDIO)

                (hasFullVisualAccess || hasSelectedVisualAccess) && hasAudioAccess
            }
            else -> mediaReadPermissions().all(::hasPermission)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            permission,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun mediaReadPermissions(): Array<String> {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
            )
            else -> arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
            )
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

    private fun appPreferences() = getSharedPreferences(APP_PREFS, Context.MODE_PRIVATE)

    private enum class PermissionKind {
        STORAGE,
        MEDIA,
    }

    private data class FolderAccumulator(
        var sizeBytes: Long = 0L,
        var fileCount: Int = 0,
        var lastModified: Long = 0L,
    )

    private data class CategoryAccumulator(
        var fileCount: Int = 0,
        var totalBytes: Long = 0L,
    )

    private data class AppStorageSnapshot(
        val appBytes: Long = 0L,
        val dataBytes: Long = 0L,
        val cacheBytes: Long = 0L,
    ) {
        val totalBytes: Long
            get() = appBytes + dataBytes
    }

    private companion object {
        const val STORAGE_SCANNER_CHANNEL = "ai.spacepilot.app/storage_scanner"
        const val PERMISSIONS_CHANNEL = "ai.spacepilot.app/permissions"
        const val NOTIFICATIONS_CHANNEL = "ai.spacepilot.app/notifications"
        const val BACKGROUND_WORK_CHANNEL = "ai.spacepilot.app/background_work"
        const val APP_INFO_CHANNEL = "ai.spacepilot.app/app_info"
        const val AGENT_BACKGROUND_CHANNEL = "ai.spacepilot.app/agent_background"
        const val STORAGE_STATS_CHANNEL = "ai.spacepilot.app/storage_stats"
        const val APP_PREFERENCES_CHANNEL = "ai.spacepilot.app/preferences"
        const val FILE_ACTIONS_CHANNEL = "ai.spacepilot.app/file_actions"
        const val APP_ANALYZER_CHANNEL = "ai.spacepilot.app/app_analyzer"
        const val POWER_THERMAL_CHANNEL = "ai.spacepilot.app/power_thermal"
        const val RAM_BOOSTER_CHANNEL = "ai.spacepilot.app/ram_booster"
        const val APP_PREFS = "spacepilot_app_preferences"
        const val ONBOARDING_COMPLETED_KEY = "onboarding_completed"
        const val STORAGE_PERMISSION_REQUEST = 4102
        const val MEDIA_PERMISSION_REQUEST = 4103
        const val NOTIFICATION_PERMISSION_REQUEST = 4104
        const val AGENT_MONITORING_JOB_ID = 4201
        const val AGENT_MONITORING_INTERVAL_MS = 60L * 60L * 1000L
        const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L
        const val APP_USAGE_WINDOW_MS = 180L * 24L * 60L * 60L * 1000L
        const val RAM_BOOST_RECENT_APP_WINDOW_MS = 30L * 60L * 1000L
        const val MAX_RAM_BOOST_PACKAGES = 24
        const val MAX_REPORTED_FOLDERS = 50
        val STORAGE_CATEGORIES = listOf(
            "image",
            "video",
            "audio",
            "document",
            "apk",
            "zip",
            "download",
            "other",
        )
        val IMAGE_EXTENSIONS = setOf(
            "gif",
            "heic",
            "jpeg",
            "jpg",
            "png",
            "raw",
            "webp",
        )
        val VIDEO_EXTENSIONS = setOf(
            "3gp",
            "avi",
            "m4v",
            "mkv",
            "mov",
            "mp4",
            "webm",
        )
        val AUDIO_EXTENSIONS = setOf(
            "aac",
            "flac",
            "m4a",
            "mp3",
            "ogg",
            "opus",
            "wav",
            "wma",
        )
        val DOCUMENT_EXTENSIONS = setOf(
            "csv",
            "doc",
            "docx",
            "epub",
            "odp",
            "ods",
            "odt",
            "pdf",
            "ppt",
            "pptx",
            "rtf",
            "txt",
            "xls",
            "xlsx",
        )
        val ZIP_EXTENSIONS = setOf("7z", "gz", "rar", "tar", "zip")
        val SCANNED_FOLDERS = listOf(
            Environment.DIRECTORY_DOWNLOADS,
            Environment.DIRECTORY_DCIM,
            Environment.DIRECTORY_MOVIES,
            Environment.DIRECTORY_PICTURES,
        )
    }
}

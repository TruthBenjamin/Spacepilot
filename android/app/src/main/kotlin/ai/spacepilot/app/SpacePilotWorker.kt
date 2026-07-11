package ai.spacepilot.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

internal object BackgroundWorkCoordinator {
    const val CHANNEL_ID = "spacepilot_storage_alerts"
    const val RECOVERY_WORK = "spacepilot_recovery_purge"
    private const val SCHEDULED_SCAN_WORK = "spacepilot_scheduled_scan"

    fun ensureRecoveryPurge(context: Context) {
        val settings = readObject(context, "recovery_settings_v1")
        syncRecoveryPurge(context, settings?.optBoolean("autoPurge", true) != false)
    }

    fun syncRecoveryPurge(context: Context, enabled: Boolean) {
        if (!enabled) {
            WorkManager.getInstance(context).cancelUniqueWork(RECOVERY_WORK)
            return
        }
        enqueue(context, RECOVERY_WORK, "recoveryPurge", 1, 0, emptyMap())
    }

    fun syncRule(context: Context, rule: Map<*, *>) {
        val id = rule["id"] as? String ?: return
        val workName = "automation_rule_$id"
        if (rule["enabled"] != true) {
            WorkManager.getInstance(context).cancelUniqueWork(workName)
            return
        }
        val cadence = rule["cadence"] as? String
        val days = when (cadence) { "monthly" -> 30L; "weekly" -> 7L; else -> 1L }
        val data = mutableMapOf<String, Any>()
        (rule["storageWarningFreePercent"] as? Number)?.let {
            data["threshold"] = it.toInt()
        }
        enqueue(context, workName, rule["type"] as? String ?: "signal", days, 0, data)
    }

    fun syncScheduledScan(context: Context, enabled: Boolean, days: Long, delayMs: Long) {
        if (!enabled) {
            WorkManager.getInstance(context).cancelUniqueWork(SCHEDULED_SCAN_WORK)
            return
        }
        enqueue(context, SCHEDULED_SCAN_WORK, "scheduledScan", days, delayMs, emptyMap())
    }

    fun cancel(context: Context, workName: String) =
        WorkManager.getInstance(context).cancelUniqueWork(workName)

    private fun enqueue(
        context: Context,
        name: String,
        task: String,
        days: Long,
        delayMs: Long,
        extras: Map<String, Any>,
    ) {
        val data = Data.Builder().putString("task", task)
        extras.forEach { (key, value) ->
            when (value) { is Int -> data.putInt(key, value); is String -> data.putString(key, value) }
        }
        val request = PeriodicWorkRequestBuilder<SpacePilotWorker>(days.coerceAtLeast(1), TimeUnit.DAYS)
            .setInitialDelay(delayMs.coerceAtLeast(0), TimeUnit.MILLISECONDS)
            .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
            .setInputData(data.build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            name,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    private fun readObject(context: Context, key: String): JSONObject? = runCatching {
        val raw = context.getSharedPreferences("spacepilot_app_preferences", Context.MODE_PRIVATE)
            .getString(key, null) ?: return@runCatching null
        JSONObject(raw)
    }.getOrNull()
}

class SpacePilotWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = runCatching {
        when (val task = inputData.getString("task")) {
            "recoveryPurge" -> purgeExpiredRecoveryItems()
            "storageWarning" -> storageWarning(inputData.getInt("threshold", 10))
            "scheduledScan" -> notify("Scheduled storage review", "Open SpacePilot to review current storage health.")
            "monthlyReport" -> notify("Monthly storage report", "Your monthly storage review is ready in SpacePilot.")
            "weeklyScan" -> notify("Weekly storage review", "Open SpacePilot to run your scheduled review.")
            "deleteScreenshots", "deleteApkInstallers" ->
                notify("Cleanup review ready", "Open SpacePilot to review files matched by your automation rule.")
            else -> Unit
        }
        Result.success()
    }.getOrElse { Result.retry() }

    private fun storageWarning(threshold: Int) {
        val stat = android.os.StatFs(applicationContext.filesDir.absolutePath)
        val total = stat.totalBytes
        if (total <= 0) return
        val freePercent = ((stat.availableBytes * 100) / total).toInt()
        if (freePercent < threshold) {
            notify("Storage running low", "$freePercent% free space remains. Open SpacePilot to review safely.")
        }
    }

    private fun purgeExpiredRecoveryItems() {
        val prefs = applicationContext.getSharedPreferences("spacepilot_app_preferences", Context.MODE_PRIVATE)
        val settings = runCatching { JSONObject(prefs.getString("recovery_settings_v1", "{}")!!) }.getOrNull()
        if (settings?.optBoolean("autoPurge", true) == false) return
        val raw = prefs.getString("recovery_bin_items_v1", null) ?: return
        val items = runCatching { JSONArray(raw) }.getOrNull() ?: return
        val root = File(applicationContext.getExternalFilesDir(null) ?: applicationContext.filesDir, "recovery_bin").canonicalFile
        val retained = JSONArray()
        val now = System.currentTimeMillis()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            if (item.optLong("expiresAt", Long.MAX_VALUE) > now) {
                retained.put(item)
                continue
            }
            val candidate = runCatching { File(item.optString("recoveryPath")).canonicalFile }.getOrNull()
            val safelyContained = candidate != null && candidate.path.startsWith(root.path + File.separator)
            if (!safelyContained || (candidate.exists() && !candidate.delete())) retained.put(item)
        }
        prefs.edit().putString("recovery_bin_items_v1", retained.toString()).apply()
    }

    private fun notify(title: String, body: String) {
        val prefs = applicationContext.getSharedPreferences("spacepilot_app_preferences", Context.MODE_PRIVATE)
        val enabled = runCatching {
            JSONObject(prefs.getString("app_settings_v1", "{}")!!).optBoolean("notificationsEnabled", false)
        }.getOrDefault(false)
        if (!enabled || (Build.VERSION.SDK_INT >= 33 &&
                applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) return

        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(BackgroundWorkCoordinator.CHANNEL_ID, "Storage alerts", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(applicationContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(applicationContext, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(applicationContext, BackgroundWorkCoordinator.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pending).setAutoCancel(true).build()
        NotificationManagerCompat.from(applicationContext).notify(title.hashCode(), notification)
    }
}

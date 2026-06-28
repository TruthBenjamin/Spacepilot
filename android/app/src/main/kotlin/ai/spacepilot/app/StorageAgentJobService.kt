package ai.spacepilot.app

import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Context
import android.os.Environment
import android.os.StatFs

class StorageAgentJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        StorageAgentSampler.capture(this)
        jobFinished(params, false)
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        return true
    }
}

object StorageAgentSampler {
    private const val PREFS = "spacepilot_agent_snapshots"
    private const val SNAPSHOTS = "snapshots"
    private const val MAX_SNAPSHOTS = 24

    fun capture(context: Context): Map<String, Long> {
        val snapshot = currentSnapshot()

        val existing = loadSnapshots(context).toMutableList()
        existing += snapshot
        val trimmed = existing.takeLast(MAX_SNAPSHOTS)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(SNAPSHOTS, encode(trimmed))
            .apply()

        return snapshot
    }

    fun currentSnapshot(): Map<String, Long> {
        val stat = StatFs(Environment.getExternalStorageDirectory().absolutePath)
        val totalBytes = stat.blockSizeLong * stat.blockCountLong
        val freeBytes = stat.blockSizeLong * stat.availableBlocksLong
        val usedBytes = totalBytes - freeBytes
        val capturedAt = System.currentTimeMillis()

        return mapOf(
            "capturedAt" to capturedAt,
            "totalBytes" to totalBytes,
            "freeBytes" to freeBytes,
            "usedBytes" to usedBytes,
        )
    }

    fun loadSnapshots(context: Context): List<Map<String, Long>> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SNAPSHOTS, null)
            ?: return emptyList()

        return raw.split(";")
            .mapNotNull { row ->
                val parts = row.split(",")
                if (parts.size != 4) return@mapNotNull null
                val capturedAt = parts[0].toLongOrNull() ?: return@mapNotNull null
                val totalBytes = parts[1].toLongOrNull() ?: return@mapNotNull null
                val freeBytes = parts[2].toLongOrNull() ?: return@mapNotNull null
                val usedBytes = parts[3].toLongOrNull() ?: return@mapNotNull null
                mapOf(
                    "capturedAt" to capturedAt,
                    "totalBytes" to totalBytes,
                    "freeBytes" to freeBytes,
                    "usedBytes" to usedBytes,
                )
            }
    }

    private fun encode(snapshots: List<Map<String, Long>>): String {
        return snapshots.joinToString(";") { snapshot ->
            listOf(
                snapshot["capturedAt"] ?: 0,
                snapshot["totalBytes"] ?: 0,
                snapshot["freeBytes"] ?: 0,
                snapshot["usedBytes"] ?: 0,
            ).joinToString(",")
        }
    }
}

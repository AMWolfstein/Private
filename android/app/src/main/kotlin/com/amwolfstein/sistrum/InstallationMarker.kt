package com.amwolfstein.sistrum

import android.content.Context
import java.io.File

/** Shared before both headless playback and Activity initialization. The
 * no-backup marker and package timestamps retain the existing reset policy. */
internal object InstallationMarker {
    @Synchronized
    fun ensure(context: Context): Map<String, Any> = with(context) {
        val marker = File(noBackupFilesDir, "installation_state_v1")
        val markerExisted = marker.isFile
        val packageInfo = @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, 0)
        val installTimestampDelta = kotlin.math.abs(
            packageInfo.lastUpdateTime - packageInfo.firstInstallTime
        )
        val looksLikeFreshPackageInstall = installTimestampDelta <= 10_000L

        var markerCreated = markerExisted
        if (!markerExisted) {
            markerCreated = try {
                marker.parentFile?.mkdirs()
                marker.writeText(
                    "created_at=${System.currentTimeMillis()}\n" +
                        "version_code=${BuildConfig.VERSION_CODE}\n"
                )
                true
            } catch (e: Exception) {
                android.util.Log.w(
                    "Sistrum",
                    "Failed to create installation marker: ${e.message}"
                )
                false
            }
        }

        mapOf(
            "marker_existed" to markerExisted,
            "marker_created" to markerCreated,
            "fresh_package_install" to looksLikeFreshPackageInstall,
        )
    }
}

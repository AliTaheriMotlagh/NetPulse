package com.alitaheri.netpulse

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Intent
import android.net.ConnectivityManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netpulse/traffic").setMethodCallHandler { call, result ->
            when (call.method) {
                // Device-wide counters since boot; read by lib/src/counters/android.dart.
                "counters" -> result.success(
                    longArrayOf(
                        TrafficStats.getTotalRxBytes(), TrafficStats.getTotalTxBytes(),
                        TrafficStats.getMobileRxBytes(), TrafficStats.getMobileTxBytes(),
                        TrafficStats.getTotalRxPackets(), TrafficStats.getTotalTxPackets(),
                        TrafficStats.getMobileRxPackets(), TrafficStats.getMobileTxPackets(),
                    )
                )
                // Per-app totals since boot as [uid, label, rx, tx]; null until Usage access is granted.
                "apps" -> {
                    if (!hasUsageAccess()) {
                        result.success(null)
                    } else {
                        Thread {
                            try {
                                val apps = appTotals()
                                runOnUiThread { result.success(apps) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("apps", e.message, null) }
                            }
                        }.start()
                    }
                }
                "openUsageAccess" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private val labels = HashMap<Int, String>()

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    @Suppress("DEPRECATION") // TYPE_WIFI/TYPE_MOBILE remain the documented NetworkStatsManager keys.
    private fun appTotals(): List<List<Any>> {
        val nsm = getSystemService(NetworkStatsManager::class.java)
        val boot = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        val end = System.currentTimeMillis() + 60_000
        val totals = HashMap<Int, LongArray>()
        val bucket = NetworkStats.Bucket()
        for (type in intArrayOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE)) {
            val stats = try {
                nsm.querySummary(type, null, boot, end)
            } catch (e: Exception) {
                continue
            }
            while (stats.hasNextBucket()) {
                stats.getNextBucket(bucket)
                val t = totals.getOrPut(bucket.uid) { LongArray(2) }
                t[0] += bucket.rxBytes
                t[1] += bucket.txBytes
            }
            stats.close()
        }
        return totals.map { (uid, t) -> listOf(uid, labels.getOrPut(uid) { labelFor(uid) }, t[0], t[1]) }
    }

    private fun labelFor(uid: Int): String = when (uid) {
        NetworkStats.Bucket.UID_REMOVED -> "Removed apps"
        NetworkStats.Bucket.UID_TETHERING -> "Hotspot / tethering"
        0, Process.SYSTEM_UID -> "Android system"
        else -> packageManager.getPackagesForUid(uid)?.firstOrNull()?.let { pkg ->
            try {
                packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
            } catch (e: Exception) {
                pkg
            }
        } ?: "App $uid"
    }
}

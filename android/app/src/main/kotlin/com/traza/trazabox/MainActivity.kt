package com.traza.trazabox

import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val launcherChannel = "com.traza.trazabox/app_launcher"
    private val soundChannel = "com.traza.trazabox/sound"
    private val navChannelName = "com.traza.trazabox/navigation"
    private val ctoChannel = "com.traza.trazabox/cto_scan"

    private var navChannel: MethodChannel? = null
    private var llegadaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        navChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navChannelName)
        deliverNotificationRoute(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ctoChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "openCtoScan") {
                    result.error(
                        "CTO_UNAVAILABLE",
                        "Scanner CTO nativo no instalado en este build",
                        null,
                    )
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launcherChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> {
                        val pkg = call.arguments as? String ?: ""
                        val installed = try {
                            packageManager.getPackageInfo(pkg, 0)
                            true
                        } catch (_: PackageManager.NameNotFoundException) {
                            false
                        }
                        result.success(installed)
                    }
                    "launchApp" -> {
                        val pkg = call.arguments as? String ?: ""
                        val intent = packageManager.getLaunchIntentForPackage(pkg)
                        if (intent != null) {
                            startActivity(intent)
                            result.success(null)
                        } else {
                            result.error("NOT_FOUND", "App no instalada: $pkg", null)
                        }
                    }
                    "installApkFromPath" -> {
                        val filePath = call.arguments as? String ?: ""
                        try {
                            val apkFile = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playAlerta" -> {
                        MaterialAlertNotifier.playAlertaFromDart(this)
                        result.success(null)
                    }
                    "stopAlerta" -> {
                        MaterialAlertNotifier.stopAlerta()
                        result.success(null)
                    }
                    "cancelMaterialNotificacion" -> {
                        MaterialAlertNotifier.cancelMaterialNotification(this)
                        result.success(null)
                    }
                    "playAyuda" -> {
                        MaterialAlertNotifier.playAyudaFromDart(this)
                        result.success(null)
                    }
                    "playMaterialLlegada" -> {
                        try {
                            llegadaPlayer?.stop()
                            llegadaPlayer?.release()
                            val mp = MediaPlayer.create(this, R.raw.alerta_urgente)
                            llegadaPlayer = mp
                            mp?.setOnCompletionListener {
                                it.release()
                                if (llegadaPlayer === it) llegadaPlayer = null
                            }
                            mp?.start()
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"),
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverNotificationRoute(intent)
    }

    private fun deliverNotificationRoute(intent: Intent?) {
        if (intent == null) return

        val route = intent.getStringExtra("trazabox_route") ?: return
        val solicitudId = intent.getStringExtra("trazabox_solicitud_id")
        val ticketId = intent.getStringExtra("trazabox_ticket_id")
        intent.removeExtra("trazabox_route")
        intent.removeExtra("trazabox_solicitud_id")
        intent.removeExtra("trazabox_ticket_id")
        val extras = mutableMapOf<String, String>("route" to route)
        solicitudId?.let { extras["solicitud_id"] = it }
        ticketId?.let { extras["ticket_id"] = it }
        if (extras.size > 1) {
            navChannel?.invokeMethod("openRoute", extras)
        } else {
            navChannel?.invokeMethod("openRoute", route)
        }
    }

    override fun onPause() {
        AppVisibility.activityResumed = false
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        AppVisibility.activityResumed = true
    }
}

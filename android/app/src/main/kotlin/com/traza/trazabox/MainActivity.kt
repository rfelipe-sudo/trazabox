package com.traza.trazabox

import android.app.Activity
import android.content.Intent
import android.app.PendingIntent
import android.content.pm.PackageInstaller
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
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private val launcherChannel = "com.traza.trazabox/app_launcher"
    private val soundChannel = "com.traza.trazabox/sound"
    private val navChannelName = "com.traza.trazabox/navigation"
    private val ctoChannel = "com.traza.trazabox/cto_scan"
    private val updateChannelName = "com.traza.trazabox/update"

    private var navChannel: MethodChannel? = null
    private var llegadaPlayer: MediaPlayer? = null
    private var launcherMethodChannel: MethodChannel? = null
    private var updateChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        navChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navChannelName)
        deliverNotificationRoute(intent)

        // ── Auto-actualización: instala con PackageInstaller (sesión) y Android
        //    relanza esta Activity cuando la instalación termina. ───────────────
        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
        updateChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApkSession" -> installApkSession(call.arguments as? String ?: "", result)
                else -> result.notImplemented()
            }
        }
        handleInstallStatusIntent(intent)

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

        launcherMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launcherChannel)
        launcherMethodChannel!!.setMethodCallHandler { call, result ->
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
                    "openAppTecnicoWebView" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, String>()
                        val url = args["url"]?.toString() ?: ""
                        val username = args["username"]?.toString()
                        val password = args["password"]?.toString()
                        if (url.isBlank()) {
                            result.error("NO_URL", "URL requerida", null)
                        } else {
                            val intent = Intent(this, AppTecnicoActivity::class.java)
                            intent.putExtra(AppTecnicoActivity.EXTRA_URL, url)
                            if (!username.isNullOrBlank() && !password.isNullOrBlank()) {
                                intent.putExtra(AppTecnicoActivity.EXTRA_AUTO_USERNAME, username)
                                intent.putExtra(AppTecnicoActivity.EXTRA_AUTO_PASSWORD, password)
                            }
                            startActivityForResult(intent, REQ_APP_TECNICO)
                            result.success(null)
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
                    "playComunicado" -> {
                        try {
                            val mp = MediaPlayer.create(this, R.raw.alerta_supervisor)
                            mp?.setOnCompletionListener { it.release() }
                            mp?.start()
                        } catch (_: Exception) {
                        }
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
        handleInstallStatusIntent(intent)
    }

    private fun installApkSession(filePath: String, result: MethodChannel.Result) {
        try {
            val apkFile = File(filePath)
            if (!apkFile.exists()) {
                result.error("APK_NOT_FOUND", "APK no encontrado: $filePath", null)
                return
            }
            if (apkFile.length() < 1024L * 100L) {
                result.error("APK_TOO_SMALL", "APK incompleto (${apkFile.length()} bytes)", null)
                return
            }
            if (!packageManager.canRequestPackageInstalls()) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                )
                result.error(
                    "INSTALL_PERMISSION",
                    "Permite instalar apps desconocidas para TrazaBox y vuelve a abrir la app",
                    null,
                )
                return
            }

            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            params.setAppPackageName(packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Si TrazaBox ya es el instalador de registro, Android puede
                // actualizar sin pedir confirmación; si no, pide "Instalar" igual.
                params.setRequireUserAction(
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                )
            }
            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            session.openWrite("trazabox.apk", 0, apkFile.length()).use { out ->
                FileInputStream(apkFile).use { input -> input.copyTo(out) }
                session.fsync(out)
            }

            val statusIntent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_INSTALL_STATUS
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val pending = PendingIntent.getActivity(this, sessionId, statusIntent, flags)
            session.commit(pending.intentSender)
            session.close()
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_ERROR", e.message, null)
        }
    }

    /// Estado de la sesión de instalación (llega a esta Activity vía PendingIntent).
    private fun handleInstallStatusIntent(intent: Intent?) {
        if (intent == null || intent.action != ACTION_INSTALL_STATUS) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)
        if (status == Int.MIN_VALUE) return
        intent.action = null
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        startActivity(confirm)
                    } catch (e: Exception) {
                        updateChannel?.invokeMethod(
                            "installStatus",
                            mapOf("status" to "failure", "message" to (e.message ?: "No se pudo abrir la confirmación")),
                        )
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                // Ya somos la versión nueva: Android relanzó la app sola.
            }
            else -> {
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Instalación no completada (código $status)"
                val tipo = if (status == PackageInstaller.STATUS_FAILURE_ABORTED) "aborted" else "failure"
                updateChannel?.invokeMethod(
                    "installStatus",
                    mapOf("status" to tipo, "message" to msg),
                )
            }
        }
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_APP_TECNICO) {
            if (resultCode == AppTecnicoActivity.RESULT_CREDENTIALS_ERROR) {
                launcherMethodChannel?.invokeMethod("credentialsError", null)
            } else {
                launcherMethodChannel?.invokeMethod("appTecnicoClosed", null)
            }
        }
    }

    companion object {
        private const val REQ_APP_TECNICO = 9001
        const val ACTION_INSTALL_STATUS = "com.traza.trazabox.INSTALL_STATUS"
    }
}

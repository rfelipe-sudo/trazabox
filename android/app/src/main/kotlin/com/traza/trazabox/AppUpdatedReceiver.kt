package com.traza.trazabox

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Respaldo del relanzamiento tras auto-actualización: si el PendingIntent de la
 * sesión de instalación no levantó la app, Android avisa aquí que el paquete fue
 * reemplazado y se intenta abrir MainActivity.
 */
class AppUpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (AppVisibility.activityResumed) return
        try {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.w("AppUpdatedReceiver", "No se pudo relanzar tras actualizar: ${e.message}")
        }
    }
}

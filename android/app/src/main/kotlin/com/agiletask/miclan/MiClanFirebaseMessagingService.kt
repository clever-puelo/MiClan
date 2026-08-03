package com.agiletask.miclan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MiClanFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "MiClanFCM"
        private const val CHANNEL_ID_CRITICAL = "miclan_critical_channel"
        private const val CHANNEL_ID_NORMAL = "miclan_normal_channel"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d(TAG, "Mensaje FCM recibido: ${remoteMessage.data}")

        val commandType = remoteMessage.data["type"]
        val payload = remoteMessage.data["payload"] ?: ""

        if (commandType == null) return

        when (commandType) {
            "ALARMA_SOS" -> {
                showCriticalNotification("🚨 ALERTA DE EMERGENCIA", "Se ha activado una alerta S.O.S", NotificationCompat.PRIORITY_MAX)
            }
            "PING_GPS" -> {
                showCriticalNotification("📍 SOLICITUD DE UBICACIÓN", "El supervisor solicita tu ubicación actual", NotificationCompat.PRIORITY_HIGH)
            }
            "MENSAJE_TEXTO" -> {
                showNormalNotification("💬 Mensaje del Supervisor", payload)
            }
            "CAPTURA_FOTO" -> {
                showNormalNotification("📷 Captura de Foto", "Se ha solicitado una captura de foto")
            }
            "REINICIO_SERVICIO" -> {
                showNormalNotification("🔄 Reinicio de Servicio", "El servicio de rastreo se está reiniciando")
            }
        }
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "Nuevo token FCM: $token")
    }

    private fun showCriticalNotification(title: String, message: String, priority: Int) {
        createNotificationChannel(CHANNEL_ID_CRITICAL, "Alertas Criticas", NotificationManager.IMPORTANCE_HIGH)

        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        val vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID_CRITICAL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(priority)
            .setSound(sound)
            .setVibrate(vibrationPattern)
            .setAutoCancel(true)
            .setFullScreenIntent(null, true)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun showNormalNotification(title: String, message: String) {
        createNotificationChannel(CHANNEL_ID_NORMAL, "Notificaciones Normales", NotificationManager.IMPORTANCE_DEFAULT)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID_NORMAL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun createNotificationChannel(channelId: String, channelName: String, importance: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = "Canal para $channelName"
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
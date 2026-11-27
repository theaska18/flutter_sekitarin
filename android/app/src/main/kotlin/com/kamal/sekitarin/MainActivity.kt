package com.kamal.sekitarin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                "sekitar_chat",
                "Chat Sekitarin",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Pesan dan notifikasi chat Sekitarin"
            channel.enableVibration(true)
            channel.enableLights(true)
            channel.setShowBadge(true)
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()
            channel.setSound(soundUri, attributes)
            manager.createNotificationChannel(channel)
        }
    }
}

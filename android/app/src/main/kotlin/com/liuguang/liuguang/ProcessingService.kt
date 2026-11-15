package com.liuguang.liuguang

import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.IBinder
import android.os.Build
import android.content.pm.ServiceInfo

class ProcessingService : Service() {
    companion object { @Volatile var running = false }
    override fun onCreate() { super.onCreate(); running = true }
    override fun onDestroy() { running = false; super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("processing", "图片处理", NotificationManager.IMPORTANCE_LOW))
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        val notification = Notification.Builder(this, "processing")
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setContentTitle("琉光正在处理图片")
            .setContentText("点击返回查看任务；任务完成后自动结束")
            .setContentIntent(pending).setOngoing(true).build()
        val local = intent?.getBooleanExtra("local", false) == true
        val cloud = intent?.getBooleanExtra("cloud", true) != false
        val type = (if (cloud || Build.VERSION.SDK_INT < 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0) or (if (local && Build.VERSION.SDK_INT >= 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING else 0)
        startForeground(105, notification, type)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
}

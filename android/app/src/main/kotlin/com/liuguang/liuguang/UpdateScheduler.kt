package com.liuguang.liuguang

import android.app.*
import android.app.job.*
import android.content.*
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.Future

object UpdateScheduler {
    const val JOB = 914
    private const val PREFS = "liuguang_updates"
    fun configure(context: Context, enabled: Boolean, notify: Boolean, source: String, version: String) {
        context.getSharedPreferences(PREFS, 0).edit().putBoolean("enabled", enabled)
            .putBoolean("notify", notify).putString("source", source).putString("version", version).apply()
        schedule(context)
    }
    fun enabled(context: Context) = context.getSharedPreferences(PREFS, 0).getBoolean("enabled", false)
    fun schedule(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(context, JOB, Intent(context, UpdateAlarmReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.cancel(pending)
        if (!enabled(context)) { context.getSystemService(JobScheduler::class.java).cancel(JOB); return }
        val now = System.currentTimeMillis()
        val next = Calendar.getInstance().apply {
            set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0); set(Calendar.HOUR_OF_DAY, 9)
            if (timeInMillis <= now) set(Calendar.HOUR_OF_DAY, 21)
            if (timeInMillis <= now) { add(Calendar.DAY_OF_YEAR, 1); set(Calendar.HOUR_OF_DAY, 9) }
        }
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, pending)
    }
    fun check(context: Context) {
        if (!enabled(context)) return
        val prefs = context.getSharedPreferences(PREFS, 0)
        val github = prefs.getString("source", "gitee") == "github"
        val endpoint = if (github) "https://api.github.com/repos/HighnessRK/liuguang/releases/latest"
            else "https://gitee.com/api/v5/repos/highnesssrk/liuguang/releases?per_page=50"
        val connection = URL(endpoint).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15000; connection.readTimeout = 15000
            connection.setRequestProperty("User-Agent", "liuguang-updater")
            if (connection.responseCode != 200) return
            val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val releases = if (github) listOf(JSONObject(body)) else JSONArray(body).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
            val best = releases.filter { !it.optBoolean("draft") && !it.optBoolean("prerelease") }
                .maxWithOrNull { a,b -> compare(a.optString("tag_name"), b.optString("tag_name")) } ?: return
            val tag = best.optString("tag_name")
            if (compare(tag, prefs.getString("version", "1.0.0")!!) <= 0 || !prefs.getBoolean("notify", true) || prefs.getString("notified", "") == tag) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (!manager.areNotificationsEnabled()) return
            manager.createNotificationChannel(NotificationChannel("updates", "应用更新", NotificationManager.IMPORTANCE_DEFAULT))
            val pending = PendingIntent.getActivity(context, JOB, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.notify(JOB, Notification.Builder(context, "updates").setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("琉光发现新版本 $tag").setContentText("点击打开应用查看更新并下载安装")
                .setContentIntent(pending).setAutoCancel(true).build())
            prefs.edit().putString("notified", tag).apply()
        } finally { connection.disconnect() }
    }
    private fun compare(a: String,b: String): Int {
        fun parts(v: String) = v.trim().removePrefix("v").removePrefix("V").split('.', '+', '-').take(3).map { it.toIntOrNull() ?: 0 }
        val x=parts(a); val y=parts(b)
        for (i in 0..2) { val c=(x.getOrElse(i){0}).compareTo(y.getOrElse(i){0}); if(c!=0) return c }
        return 0
    }
}
class UpdateAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        UpdateScheduler.schedule(context)
        if (!UpdateScheduler.enabled(context) || intent.action != null) return
        context.getSystemService(JobScheduler::class.java).schedule(JobInfo.Builder(UpdateScheduler.JOB, ComponentName(context, UpdateCheckJob::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setBackoffCriteria(30*60*1000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build())
    }
}
class UpdateCheckJob : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private var task: Future<*>? = null
    override fun onStartJob(params: JobParameters): Boolean {
        task=executor.submit { var retry=false; try { UpdateScheduler.check(this) } catch (_:Exception) { retry=true }; if (!Thread.currentThread().isInterrupted) jobFinished(params,retry) }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean { task?.cancel(true);return true }
    override fun onDestroy() { executor.shutdownNow();super.onDestroy() }
}

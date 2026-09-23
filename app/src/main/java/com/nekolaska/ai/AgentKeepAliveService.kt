package com.nekolaska.ai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import github.znzsofficial.neluaj.R

/**
 * Agent 回合的前台保活服务：回合进行中提升进程优先级并持有唤醒锁，
 * 防止息屏后流式请求与工具执行被系统挂起。Lua 侧在每个模型请求开始时
 * [acquire]，回合结束时 [release]；服务自带看门狗，Lua 循环异常退出时
 * 自动停止，不会留下常驻通知或锁。
 */
class AgentKeepAliveService : Service() {

    companion object {
        private const val ACTION_ACQUIRE = "com.nekolaska.ai.keepalive.ACQUIRE"
        private const val CHANNEL_ID = "agent_keepalive"
        private const val NOTIFICATION_ID = 4700
        private const val WAKELOCK_TAG = "neluaj:agent_keepalive"
        private const val WIFILOCK_TAG = "neluaj:agent_keepalive"

        /** 看门狗时长；工具链每轮模型请求都会重新 acquire 续期。 */
        private const val WATCHDOG_MS = 15 * 60 * 1000L

        @JvmStatic
        fun acquire(context: Context) {
            val intent = Intent(context, AgentKeepAliveService::class.java)
                .setAction(ACTION_ACQUIRE)
            ContextCompat.startForegroundService(context, intent)
        }

        @JvmStatic
        fun release(context: Context) {
            // stopService 允许从后台调用：回合可能在息屏期间结束。
            context.stopService(Intent(context, AgentKeepAliveService::class.java))
        }
    }

    private val watchdog = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private val onWatchdog = Runnable { stopKeepAlive() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_ACQUIRE) {
            stopKeepAlive()
            return START_NOT_STICKY
        }
        enterForeground()
        acquireLocks()
        watchdog.removeCallbacks(onWatchdog)
        watchdog.postDelayed(onWatchdog, WATCHDOG_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopKeepAlive()
    }

    private fun enterForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.agent_keepalive_channel),
                NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.icon)
            .setContentTitle(getString(R.string.agent_keepalive_title))
            .setContentText(getString(R.string.agent_keepalive_text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this, 0, launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        ServiceCompat.startForeground(
            this, NOTIFICATION_ID, builder.build(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        )
    }

    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = (wakeLock ?: power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG))
                .apply {
                    setReferenceCounted(false)
                    runCatching { acquire(WATCHDOG_MS) }
                }
        }
        if (wifiLock?.isHeld != true) {
            runCatching {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = (wifiLock ?: wifi.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF, WIFILOCK_TAG
                )).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        }
    }

    private fun cleanup() {
        watchdog.removeCallbacks(onWatchdog)
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
        wifiLock = null
    }

    private fun stopKeepAlive() {
        cleanup()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}

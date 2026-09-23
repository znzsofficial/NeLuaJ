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
 * [acquire]，回合结束时 [release]。
 *
 * 看门狗分层：每 [WATCHDOG_MS] 检查一次续期；连续未续期时先只释放锁
 * （服务与通知保留，续期后恢复），连续 [MAX_WATCHDOG_MISSES] 轮未续期
 * 才整体停止——避免超过单个请求时长的长回合被误杀后，下一次 acquire
 * 在后台启动前台服务被系统拒绝。
 */
class AgentKeepAliveService : Service() {

    companion object {
        private const val ACTION_ACQUIRE = "com.nekolaska.ai.keepalive.ACQUIRE"
        private const val CHANNEL_ID = "agent_keepalive"
        private const val NOTIFICATION_ID = 4700
        private const val WAKELOCK_TAG = "neluaj:agent_keepalive"
        private const val WIFILOCK_TAG = "neluaj:agent_keepalive"

        /** 看门狗间隔；工具链每轮模型请求都会重新 acquire 续期。 */
        private const val WATCHDOG_MS = 15 * 60 * 1000L

        /** 连续未续期达到该轮数才停止服务（15 分钟 × 4 = 1 小时）。 */
        private const val MAX_WATCHDOG_MISSES = 4

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
    private var watchdogMisses = 0
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private val onWatchdog: Runnable = Runnable {
        watchdogMisses += 1
        if (watchdogMisses >= MAX_WATCHDOG_MISSES) {
            stopKeepAlive()
            return@Runnable
        }
        // 一轮未续期：先释放锁让硬件休息，服务与通知保留，等待续期恢复
        releaseLocks()
        watchdog.postDelayed(onWatchdog, WATCHDOG_MS)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_ACQUIRE) {
            stopKeepAlive()
            return START_NOT_STICKY
        }
        enterForeground()
        watchdogMisses = 0
        watchdog.removeCallbacks(onWatchdog)
        watchdog.postDelayed(onWatchdog, WATCHDOG_MS)
        acquireLocks()
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
            .setSmallIcon(R.drawable.ic_agent_notify)
            .setContentTitle(getString(R.string.agent_keepalive_title))
            .setContentText(getString(R.string.agent_keepalive_text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
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
        // 唤醒锁必须先释放再重新计时：直接重复 acquire 不会延长原超时
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val lock = wakeLock ?: power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)
        lock.setReferenceCounted(false)
        runCatching { lock.acquire(WATCHDOG_MS) }
        wakeLock = lock

        if (wifiLock?.isHeld != true) {
            runCatching {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val wifiLockNew = wifiLock ?: wifi.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF, WIFILOCK_TAG
                )
                wifiLockNew.setReferenceCounted(false)
                wifiLockNew.acquire()
                wifiLock = wifiLockNew
            }
        }
    }

    private fun releaseLocks() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
    }

    private fun cleanup() {
        watchdog.removeCallbacks(onWatchdog)
        releaseLocks()
        wakeLock = null
        wifiLock = null
    }

    private fun stopKeepAlive() {
        cleanup()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}

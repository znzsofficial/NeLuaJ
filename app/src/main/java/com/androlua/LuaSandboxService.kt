package com.androlua

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.Process
import android.os.ResultReceiver
import android.os.SystemClock
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Runs untrusted Lua only in the private `:lua_sandbox` process. */
class LuaSandboxService : Service() {
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "lua-sandbox-worker")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_CANCEL) {
            Process.killProcess(Process.myPid())
            return START_NOT_STICKY
        }
        val code = intent?.getStringExtra(KEY_CODE)
        val timeout = intent?.getLongExtra(KEY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS)
            ?.coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
            ?: DEFAULT_TIMEOUT_MS
        val deadline = intent?.getLongExtra(
            KEY_DEADLINE_ELAPSED_MS,
            SystemClock.elapsedRealtime() + timeout
        ) ?: SystemClock.elapsedRealtime() + timeout
        val allowedHosts = intent?.getStringExtra(KEY_ALLOWED_HOSTS).orEmpty()
        @Suppress("DEPRECATION")
        val receiver = intent?.getParcelableExtra<ResultReceiver>(KEY_RECEIVER)

        if ((action != ACTION_RUN && action != ACTION_CHECK_SYNTAX) || code == null || receiver == null) {
            receiver?.send(0, SandboxResult(false, "", "invalid sandbox request", 0).toBundle())
            stopSelf(startId)
            return START_NOT_STICKY
        }

        worker.execute {
            val result = execute(code, deadline, action, allowedHosts)
            receiver.send(0, result.toBundle())
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun execute(code: String, deadline: Long, action: String, allowedHosts: String): SandboxResult {
        val start = System.currentTimeMillis()
        val remaining = deadline - SystemClock.elapsedRealtime()
        if (remaining <= 0) {
            return SandboxResult(false, "", "sandbox request timed out", 0)
        }
        val completed = AtomicBoolean(false)
        val watchdog = WATCHDOG.schedule({
            if (completed.compareAndSet(false, true)) {
                Process.killProcess(Process.myPid())
            }
        }, remaining, TimeUnit.MILLISECONDS)

        return try {
            val result = if (action == ACTION_RUN) {
                SandboxExecution.run(code, SandboxHttp.parseAllowedHosts(allowedHosts))
            } else {
                val error = SandboxExecution.checkSyntax(code)
                SandboxResult(error == null, "", error.orEmpty(), System.currentTimeMillis() - start)
            }
            if (completed.compareAndSet(false, true)) {
                watchdog.cancel(false)
                result
            } else {
                SandboxResult(false, "", "sandbox process timed out", remaining)
            }
        } catch (failure: Throwable) {
            if (completed.compareAndSet(false, true)) {
                watchdog.cancel(false)
                SandboxResult(
                    false,
                    "",
                    failure.message ?: "sandbox runtime failure",
                    System.currentTimeMillis() - start
                )
            } else {
                SandboxResult(false, "", "sandbox process timed out", remaining)
            }
        }
    }

    companion object {
        const val ACTION_RUN = "com.androlua.action.RUN_LUA_SANDBOX"
        const val ACTION_CHECK_SYNTAX = "com.androlua.action.CHECK_LUA_SANDBOX_SYNTAX"
        const val ACTION_CANCEL = "com.androlua.action.CANCEL_LUA_SANDBOX"
        const val KEY_CODE = "code"
        const val KEY_TIMEOUT_MS = "timeoutMs"
        const val KEY_DEADLINE_ELAPSED_MS = "deadlineElapsedMs"
        const val KEY_ALLOWED_HOSTS = "allowedHosts"
        const val KEY_RECEIVER = "receiver"
        const val KEY_OK = "ok"
        const val KEY_OUTPUT = "output"
        const val KEY_ERROR = "error"
        const val KEY_ELAPSED_MS = "elapsed"

        private const val MIN_TIMEOUT_MS = 1_000L
        private const val MAX_TIMEOUT_MS = 8_000L
        private const val DEFAULT_TIMEOUT_MS = 3_000L
        private val WATCHDOG = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "lua-sandbox-watchdog").apply { isDaemon = true }
        }
    }
}

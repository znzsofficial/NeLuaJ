package com.androlua

import android.content.Intent
import android.os.Bundle
import android.os.ResultReceiver
import android.os.SystemClock
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.jse.JsePlatform
import com.nekolaska.ktx.standardError
import com.nekolaska.ktx.standardOutput
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * AI agent Lua sandbox entry point.
 *
 * Execution runs in the private `:lua_sandbox` process. A timeout kills that process rather than
 * leaving an uninterruptible Lua loop behind in the app process.
 */
object LuaSandbox {
    private const val MIN_TIMEOUT_MS = 1_000L
    private const val MAX_TIMEOUT_MS = 8_000L
    private const val DEFAULT_SYNTAX_TIMEOUT_MS = 3_000L

    @JvmStatic
    @Synchronized
    fun checkSyntax(code: String): String? {
        val result = request(LuaSandboxService.ACTION_CHECK_SYNTAX, code, DEFAULT_SYNTAX_TIMEOUT_MS)
        return if (result.ok) null else result.error
    }

    /** Runs sandbox code synchronously and returns `{ ok, output, error, elapsed }`. */
    @JvmStatic
    @Synchronized
    fun run(code: String, timeoutMs: Long): LuaTable {
        return run(code, timeoutMs, "")
    }

    /** Runs with newline-delimited HTTPS hosts explicitly authorized by the user. */
    @JvmStatic
    @Synchronized
    fun run(code: String, timeoutMs: Long, allowedHosts: String): LuaTable {
        val normalizedHosts = try {
            SandboxHttp.parseAllowedHosts(allowedHosts).joinToString("\n")
        } catch (failure: Throwable) {
            return SandboxResult(false, "", failure.message ?: "invalid sandbox HTTP hosts", 0).toLuaTable()
        }
        val timeout = timeoutMs.coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
        return request(LuaSandboxService.ACTION_RUN, code, timeout, normalizedHosts).toLuaTable()
    }

    /** Stops the remote sandbox process, including a blocked HTTP call. */
    @JvmStatic
    fun cancelPending() {
        runCatching {
            LuaApplication.instance.startService(
                Intent(LuaApplication.instance, LuaSandboxService::class.java).apply {
                    action = LuaSandboxService.ACTION_CANCEL
                }
            )
        }
    }

    private fun request(action: String, code: String, timeout: Long, allowedHosts: String = ""): SandboxResult {
        val start = System.currentTimeMillis()
        val deadline = SystemClock.elapsedRealtime() + timeout
        val receiver = SandboxResultReceiver()
        return try {
            val service = LuaApplication.instance.startService(
                Intent(LuaApplication.instance, LuaSandboxService::class.java).apply {
                    this.action = action
                    putExtra(LuaSandboxService.KEY_CODE, code)
                    putExtra(LuaSandboxService.KEY_TIMEOUT_MS, timeout)
                    putExtra(LuaSandboxService.KEY_DEADLINE_ELAPSED_MS, deadline)
                    putExtra(LuaSandboxService.KEY_ALLOWED_HOSTS, allowedHosts)
                    putExtra(LuaSandboxService.KEY_RECEIVER, receiver)
                }
            )
            if (service == null) {
                return SandboxResult(false, "", "sandbox service could not be started", elapsedSince(start))
            }
            val remaining = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0)
            if (remaining > 0 && receiver.await(remaining)) {
                receiver.result ?: SandboxResult(
                    false,
                    "",
                    "sandbox process returned no result",
                    elapsedSince(start)
                )
            } else {
                SandboxResult(
                    false,
                    "",
                    "${if (action == LuaSandboxService.ACTION_RUN) "execution" else "syntax check"} timed out after ${timeout / 1_000} seconds",
                    elapsedSince(start)
                )
            }
        } catch (exception: Exception) {
            SandboxResult(
                false,
                "",
                "sandbox process failed: ${exception.message ?: exception.javaClass.simpleName}",
                elapsedSince(start)
            )
        }
    }

    private fun elapsedSince(start: Long): Long = System.currentTimeMillis() - start

    private class SandboxResultReceiver : ResultReceiver(null) {
        private val latch = CountDownLatch(1)
        @Volatile
        var result: SandboxResult? = null
            private set

        override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
            result = SandboxResult.fromBundle(resultData)
            latch.countDown()
        }

        fun await(timeout: Long): Boolean = latch.await(timeout, TimeUnit.MILLISECONDS)
    }
}

/** Pure-JVM sandbox execution used by the remote provider and local unit tests. */
internal object SandboxExecution {
    private const val MAX_CODE_BYTES = 128 * 1024
    private const val MAX_OUTPUT_BYTES = 64 * 1024

    fun checkSyntax(code: String): String? {
        validateCode(code)?.let { return it }
        return try {
            sandboxGlobals().load(code, "@agent_sandbox")
            null
        } catch (error: Throwable) {
            error.message ?: "syntax error"
        }
    }

    fun run(code: String, allowedHosts: Set<String> = emptySet()): SandboxResult {
        val start = System.currentTimeMillis()
        validateCode(code)?.let { return SandboxResult(false, "", it, elapsedSince(start)) }

        val output = LimitedOutputStream(MAX_OUTPUT_BYTES)
        val stream = PrintStream(output, true, StandardCharsets.UTF_8.name())
        var ok = false
        var error = ""
        try {
            val globals = sandboxGlobals()
            val httpSession = SandboxHttp.install(globals, allowedHosts)
            globals.standardOutput = stream
            globals.standardError = stream
            try {
                val returned = globals.load(code, "@agent_sandbox").invoke()
                if (returned.narg() > 0) {
                    if (!output.isEmpty()) stream.println()
                    val values = ArrayList<String>(returned.narg())
                    for (index in 1..returned.narg()) values.add(SandboxLibraries.inspect(returned.arg(index)))
                    stream.println("[return] ${values.joinToString(", ")}")
                }
                ok = true
            } finally {
                httpSession.close()
            }
        } catch (failure: Throwable) {
            error = SandboxResult.boundError(failure.message ?: "runtime error")
        } finally {
            stream.flush()
            stream.close()
        }
        return SandboxResult(ok, output.text(), error, elapsedSince(start))
    }

    private fun sandboxGlobals() = JsePlatform.sandboxGlobals().also(SandboxLibraries::install)

    private fun validateCode(code: String): String? =
        if (code.toByteArray(StandardCharsets.UTF_8).size > MAX_CODE_BYTES) {
            "sandbox source exceeds the ${MAX_CODE_BYTES / 1024} KiB limit"
        } else {
            null
        }

    private fun elapsedSince(start: Long): Long = System.currentTimeMillis() - start

    private class LimitedOutputStream(private val limit: Int) : OutputStream() {
        private val buffer = ByteArrayOutputStream(limit)
        private var truncated = false

        override fun write(value: Int) {
            if (buffer.size() < limit) {
                buffer.write(value)
            } else {
                truncated = true
            }
        }

        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            val remaining = limit - buffer.size()
            if (remaining <= 0) {
                if (length > 0) truncated = true
                return
            }
            val written = minOf(remaining, length)
            buffer.write(bytes, offset, written)
            if (written < length) truncated = true
        }

        fun text(): String {
            val value = buffer.toString(StandardCharsets.UTF_8.name())
            return if (truncated) "$value\n...[output truncated at ${limit / 1024} KiB]" else value
        }

        fun isEmpty(): Boolean = buffer.size() == 0
    }
}

internal data class SandboxResult(
    val ok: Boolean,
    val output: String,
    val error: String,
    val elapsed: Long
) {
    fun toBundle(): Bundle = Bundle().apply {
        putBoolean(LuaSandboxService.KEY_OK, ok)
        putString(LuaSandboxService.KEY_OUTPUT, output)
        putString(LuaSandboxService.KEY_ERROR, boundError(error))
        putLong(LuaSandboxService.KEY_ELAPSED_MS, elapsed)
    }

    fun toLuaTable(): LuaTable = LuaTable().apply {
        set("ok", LuaValue.valueOf(ok))
        set("output", LuaValue.valueOf(output))
        set("error", LuaValue.valueOf(error))
        set("elapsed", LuaValue.valueOf(elapsed))
    }

    companion object {
        private const val MAX_ERROR_CHARS = 16 * 1024
        private const val ERROR_TRUNCATION_SUFFIX = "\n...[error truncated]"

        /** Keeps cross-process result Bundles well below Binder's transaction limit. */
        internal fun boundError(error: String): String {
            if (error.length <= MAX_ERROR_CHARS) return error

            var end = MAX_ERROR_CHARS - ERROR_TRUNCATION_SUFFIX.length
            if (end > 0 && Character.isHighSurrogate(error[end - 1]) &&
                end < error.length && Character.isLowSurrogate(error[end])
            ) {
                end--
            }
            return error.substring(0, end) + ERROR_TRUNCATION_SUFFIX
        }

        fun fromBundle(bundle: Bundle?): SandboxResult? = bundle?.let {
            SandboxResult(
                it.getBoolean(LuaSandboxService.KEY_OK),
                it.getString(LuaSandboxService.KEY_OUTPUT).orEmpty(),
                it.getString(LuaSandboxService.KEY_ERROR).orEmpty(),
                it.getLong(LuaSandboxService.KEY_ELAPSED_MS)
            )
        }
    }
}

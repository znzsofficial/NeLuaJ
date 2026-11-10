package com.nekolaska.mcp.server

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** A bounded wait, with separate ownership for queued and already-running UI work.
 * Abandoning a running callback does not interrupt it or release its file-token pin.
 * The callback uses only its captured payload, never the worker's Lua interpreter.
 */
internal class McpUiCall<T>(private val release: () -> Unit, private val action: () -> T) : Runnable {
    private val state = Any()
    private var started = false
    private var abandoned = false
    private val result = CompletableFuture<T>()

    override fun run() {
        synchronized(state) {
            if (started || abandoned) return
            started = true
        }
        try { result.complete(action()) }
        catch (error: Throwable) { result.completeExceptionally(error) }
        finally { release() }
    }

    fun abandon() {
        val releaseQueued = synchronized(state) {
            if (abandoned) return
            abandoned = true
            !started
        }
        if (releaseQueued) release()
    }

    fun await(timeoutMillis: Long, cancelled: () -> Boolean): T {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        try {
            while (true) {
                if (cancelled()) throw CancellationException("MCP editor wait cancelled")
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0) throw TimeoutException("MCP editor did not respond within ${timeoutMillis}ms")
                try { return result.get(minOf(remaining, TimeUnit.MILLISECONDS.toNanos(50)), TimeUnit.NANOSECONDS) }
                catch (_: TimeoutException) { /* Check the overall deadline and cancellation. */ }
            }
        } finally {
            abandon()
        }
    }
}

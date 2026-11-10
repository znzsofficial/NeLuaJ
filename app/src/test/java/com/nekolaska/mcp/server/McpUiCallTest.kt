package com.nekolaska.mcp.server

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger

class McpUiCallTest {
    @Test(timeout = 5000) fun timedOutQueuedCallbackCannotRunLater() {
        val released = AtomicInteger()
        val calls = AtomicInteger()
        val task = McpUiCall({ released.incrementAndGet() }) { calls.incrementAndGet() }
        try { task.await(20) { false }; fail("Expected timeout") } catch (_: TimeoutException) { }
        task.run()
        task.abandon()
        assertEquals(0, calls.get())
        assertEquals(1, released.get())
    }

    @Test(timeout = 5000) fun runningCallbackRetainsItsPinAfterWaitTimesOut() {
        val released = AtomicInteger()
        val entered = CountDownLatch(1)
        val resume = CountDownLatch(1)
        val task = McpUiCall({ released.incrementAndGet() }) {
            entered.countDown()
            check(resume.await(3, TimeUnit.SECONDS))
            "finished"
        }
        val ui = Thread(task).apply { start() }
        try {
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            try { task.await(20) { false }; fail("Expected timeout") } catch (_: TimeoutException) { }
            task.abandon()
            assertEquals(0, released.get())
        } finally { resume.countDown(); ui.join(1000) }
        assertFalse(ui.isAlive)
        assertEquals(1, released.get())
        task.run()
        assertEquals(1, released.get())
    }

    @Test(timeout = 5000) fun cancellationAndInterruptionAbandonQueuedCallbacks() {
        val released = AtomicInteger()
        val cancelled = McpUiCall({ released.incrementAndGet() }) { error("must not run") }
        try { cancelled.await(1000) { true }; fail("Expected cancellation") } catch (_: CancellationException) { }
        cancelled.run()
        val interrupted = McpUiCall({ released.incrementAndGet() }) { error("must not run") }
        Thread.currentThread().interrupt()
        try { interrupted.await(1000) { false }; fail("Expected interruption") }
        catch (_: InterruptedException) { }
        finally { Thread.interrupted() }
        interrupted.run()
        assertEquals(2, released.get())
    }

    @Test fun successfulAndFailedCallbacksReleaseExactlyOnce() {
        val released = AtomicInteger()
        val success = McpUiCall({ released.incrementAndGet() }) { "ok" }
        success.run()
        assertEquals("ok", success.await(1000) { false })
        success.abandon()
        val failure = McpUiCall({ released.incrementAndGet() }) { error("UI failed") }
        failure.run()
        try { failure.await(1000) { false }; fail("Expected failure") }
        catch (error: ExecutionException) { assertEquals("UI failed", error.cause?.message) }
        failure.abandon()
        assertEquals(2, released.get())
    }
}

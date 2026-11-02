package com.nekolaska.test

import com.nekolaska.agent.AgentJobRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class AgentJobRegistryTest {
    class FakeJob(private val onCancel: () -> Unit = {}) {
        var cancelled = false
        fun cancel() { cancelled = true; onCancel() }
    }

    @After fun cleanUp() { AgentJobRegistry.cancelAll() }

    @Test fun registrationDuringCancellationRemainsTracked() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val old = FakeJob { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
        val next = FakeJob()
        AgentJobRegistry.register(old, "old")
        val result = AtomicReference<List<String>>()
        val worker = Thread { result.set(AgentJobRegistry.cancelAll()) }
        worker.start()
        try {
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            AgentJobRegistry.register(next, "new")
            assertEquals(1, AgentJobRegistry.activeCount())
        } finally {
            release.countDown()
            worker.join(5000)
        }
        assertFalse(worker.isAlive)
        assertEquals(listOf("old"), result.get())
        assertTrue(old.cancelled)
        assertFalse(next.cancelled)
        assertEquals(listOf("new"), AgentJobRegistry.cancelAll())
        assertTrue(next.cancelled)
        assertEquals(0, AgentJobRegistry.activeCount())
    }

    @Test fun reentrantRegistrationDoesNotDeadlockOrLoseNewJob() {
        val next = FakeJob()
        AgentJobRegistry.register(FakeJob { AgentJobRegistry.register(next, "next") }, "first")
        assertEquals(listOf("first"), AgentJobRegistry.cancelAll())
        assertEquals(1, AgentJobRegistry.activeCount())
        assertFalse(next.cancelled)
        AgentJobRegistry.unregister(next)
        assertEquals(0, AgentJobRegistry.activeCount())
    }
}

package com.nekolaska.mcp

import okhttp3.EventListener
import okhttp3.OkHttpClient
import org.junit.Assert.*
import org.junit.Test
import java.io.Closeable
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

class McpClientCancellationTest {
    /** Hold response bodies open so cancellation must interrupt real socket IO. */
    private class Peer(private val sse: Boolean = false, delayEndpoint: Boolean = false) : Closeable {
        private val server = ServerSocket(0)
        private val sockets = java.util.concurrent.CopyOnWriteArrayList<Socket>()
        val arrived = CountDownLatch(if (sse) 1 else 2)
        val release = CountDownLatch(1)
        val endpointRelease = CountDownLatch(if (delayEndpoint) 1 else 0)
        val url = "http://127.0.0.1:${server.localPort}/mcp"
        init {
            thread(isDaemon = true) {
                try {
                    while (!server.isClosed) {
                        val socket = server.accept()
                        sockets.add(socket)
                        thread(isDaemon = true) {
                            runCatching {
                                val input = socket.getInputStream().bufferedReader()
                                var length = 0
                                while (true) {
                                    val line = input.readLine() ?: return@runCatching
                                    if (line.isEmpty()) break
                                    if (line.startsWith("Content-Length:", true)) length = line.substringAfter(':').trim().toInt()
                                }
                                repeat(length) { input.read() }
                                val out = socket.getOutputStream()
                                arrived.countDown()
                                if (sse) {
                                    endpointRelease.await(5, TimeUnit.SECONDS)
                                    out.write(("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" +
                                        "Content-Length: 100000\r\n\r\nevent: endpoint\ndata: /messages\n\n").toByteArray())
                                    out.flush()
                                }
                                release.await(5, TimeUnit.SECONDS)
                                if (!sse) {
                                    out.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".toByteArray())
                                    out.flush()
                                }
                            }
                        }
                    }
                } catch (_: IOException) { }
            }
        }
        override fun close() {
            release.countDown()
            endpointRelease.countDown()
            server.close()
            sockets.forEach { runCatching { it.close() } }
        }
    }

    @Test fun cancellingOneHttpInvocationLeavesSiblingAlive() {
        Peer().use { peer ->
            val client = McpHttpClient()
            val first = client.newRequestGroup()
            val second = client.newRequestGroup()
            val pool = Executors.newFixedThreadPool(2)
            try {
                val a = pool.submit<Boolean> {
                    try { client.postJson(peer.url, "{}", emptyMap(), -1, first); false }
                    catch (_: IOException) { true }
                }
                val b = pool.submit<McpHttpResult> { client.postJson(peer.url, "{}", emptyMap(), -1, second) }
                assertTrue(peer.arrived.await(3, TimeUnit.SECONDS))
                first.cancel()
                first.cancel()
                assertTrue(a.get(2, TimeUnit.SECONDS))
                assertFalse(second.isCancelled())
                assertFalse(b.isDone)
                peer.release.countDown()
                assertEquals(200, b.get(2, TimeUnit.SECONDS).code())
            } finally { client.cancelAll(); pool.shutdownNow() }
        }
    }

    @Test fun cancellationBeforeRegistrationPreventsNewCallsAndWakesLateResources() {
        val created = AtomicInteger()
        val client = McpHttpClient(OkHttpClient.Builder().eventListenerFactory {
            created.incrementAndGet()
            object : EventListener() {}
        }.build())
        val group = client.newRequestGroup()
        group.cancel()
        val cancelled = AtomicInteger()
        group.register(Any()) { cancelled.incrementAndGet() }
        assertEquals(1, cancelled.get())
        try {
            client.postJson("http://127.0.0.1:1/", "{}", emptyMap(), -1, group)
            fail("cancelled group created a call")
        } catch (_: IOException) { }
        try {
            client.openSse("http://127.0.0.1:1/", emptyMap(), group)
            fail("cancelled group opened SSE")
        } catch (_: IOException) { }
        assertEquals(0, created.get())
    }

    @Test fun globalCancellationMarksOldGroupsBeforeCallbacksAndAllowsNewInvocations() {
        val client = McpHttpClient()
        val first = client.newRequestGroup()
        val second = client.newRequestGroup()
        var replacement: McpRequestGroup? = null
        val cancelled = AtomicInteger()
        val releasedCancelled = AtomicInteger()
        first.register("first") {
            assertTrue(second.isCancelled())
            replacement = client.newRequestGroup()
            cancelled.incrementAndGet()
        }
        second.register("released") { releasedCancelled.incrementAndGet() }
        second.release("released")
        second.register("active") { cancelled.incrementAndGet() }
        client.cancelAll()
        assertEquals(2, cancelled.get())
        assertEquals(0, releasedCancelled.get())
        assertTrue(first.isCancelled())
        assertTrue(second.isCancelled())
        assertFalse(replacement!!.isCancelled())
        first.register("late") { cancelled.incrementAndGet() }
        assertEquals(3, cancelled.get())
        client.cancelAll()
        assertTrue(replacement!!.isCancelled())
    }

    @Test fun sseCancellationWakesOnlyItsWaiterAndKeepsSharedConnection() {
        Peer(sse = true).use { peer ->
            val client = McpHttpClient()
            val connection = client.openSse(peer.url, emptyMap())
            val group = client.newRequestGroup()
            val sibling = client.newRequestGroup()
            val pool = Executors.newFixedThreadPool(2)
            try {
                assertNotNull(connection.awaitEndpoint(2000))
                connection.prepareResponse("1", group)
                connection.prepareResponse("2", sibling)
                val entered = CountDownLatch(2)
                val firstThread = AtomicReference<Thread>()
                val secondThread = AtomicReference<Thread>()
                val a = pool.submit<String?> {
                    firstThread.set(Thread.currentThread())
                    entered.countDown(); connection.awaitResponse("1", 120000, group)
                }
                val b = pool.submit<String?> {
                    secondThread.set(Thread.currentThread())
                    entered.countDown(); connection.awaitResponse("2", 120000, sibling)
                }
                assertTrue(entered.await(2, TimeUnit.SECONDS))
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
                while ((firstThread.get().state != Thread.State.TIMED_WAITING ||
                        secondThread.get().state != Thread.State.TIMED_WAITING) && System.nanoTime() < deadline) {
                    Thread.yield()
                }
                assertEquals(Thread.State.TIMED_WAITING, firstThread.get().state)
                assertEquals(Thread.State.TIMED_WAITING, secondThread.get().state)
                group.cancel()
                assertNull(a.get(1, TimeUnit.SECONDS))
                assertFalse(b.isDone)
                assertTrue(connection.isUsable())
                connection.cancelResponse("2")
                assertNull(b.get(1, TimeUnit.SECONDS))
                // Cancellation between group creation and waiter registration.
                try { connection.prepareResponse("3", group); fail("registered after cancellation") }
                catch (_: IOException) { }
                assertNull(connection.awaitResponse("3", 1))
            } finally { client.cancelAll(); pool.shutdownNow() }
        }
    }

    @Test fun cancelledEndpointWaitLeavesConnectingStreamForNextInvocation() {
        Peer(sse = true, delayEndpoint = true).use { peer ->
            val client = McpHttpClient()
            val first = client.newRequestGroup()
            val second = client.newRequestGroup()
            val connection = client.openSse(peer.url, emptyMap(), first)
            val pool = Executors.newFixedThreadPool(2)
            try {
                assertTrue(peer.arrived.await(2, TimeUnit.SECONDS))
                val a = pool.submit<String?> { connection.awaitEndpoint(120000, first) }
                first.cancel()
                assertNull(a.get(1, TimeUnit.SECONDS))
                assertFalse(connection.isUsable())
                assertNull(connection.getError())
                val b = pool.submit<String?> { connection.awaitEndpoint(120000, second) }
                assertFalse(b.isDone)
                peer.endpointRelease.countDown()
                assertTrue(b.get(2, TimeUnit.SECONDS)!!.endsWith("/messages"))
                assertTrue(connection.isUsable())
            } finally { client.cancelAll(); pool.shutdownNow() }
        }
    }
}

package com.nekolaska.ai

import okhttp3.MediaType.Companion.toMediaType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentFetchTest {
    @Test
    fun requestValidationOnlyAllowsPublicHttpsGetAndHead() {
        val get = AgentFetch.validateRequest("https://example.com/docs", null, 0, 0)
        val head = AgentFetch.validateRequest("https://example.com/", "head", 20_000, 100_000)

        assertEquals("GET", get.method)
        assertEquals(8_000, get.timeoutMs)
        assertEquals(12_000, get.maxChars)
        assertEquals("HEAD", head.method)
        assertEquals(15_000, head.timeoutMs)
        assertEquals(50_000, head.maxChars)
        assertTrue(runCatching { AgentFetch.validateRequest("http://example.com", "GET", 0, 0) }.isFailure)
        assertTrue(runCatching { AgentFetch.validateRequest("https://127.0.0.1", "GET", 0, 0) }.isFailure)
        assertTrue(runCatching { AgentFetch.validateRequest("https://localhost", "GET", 0, 0) }.isFailure)
        assertTrue(runCatching { AgentFetch.validateRequest("https://example.com:8443", "GET", 0, 0) }.isFailure)
        assertTrue(runCatching { AgentFetch.validateRequest("https://user:pass@example.com", "GET", 0, 0) }.isFailure)
        assertTrue(runCatching { AgentFetch.validateRequest("https://example.com", "POST", 0, 0) }.isFailure)
    }

    @Test
    fun contentTypeValidationRejectsBinaryBodies() {
        assertTrue(AgentFetch.isTextual("text/html; charset=utf-8".toMediaType()))
        assertTrue(AgentFetch.isTextual("application/json".toMediaType()))
        assertTrue(AgentFetch.isTextual("application/problem+json".toMediaType()))
        assertTrue(AgentFetch.isTextual("application/xml".toMediaType()))
        assertFalse(AgentFetch.isTextual("application/octet-stream".toMediaType()))
        assertFalse(AgentFetch.isTextual("image/png".toMediaType()))
        assertFalse(AgentFetch.isTextual(null))
    }
}

package com.androlua

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LuaSandboxTest {
    @Test
    fun executionUsesRestrictedGlobalsAndCapturesOutput() {
        val result = SandboxExecution.run("print('safe'); return luajava, io, package")

        assertTrue(result.ok)
        assertEquals("safe", result.output.trim())
    }

    @Test
    fun executionBoundsOutputAndRejectsOversizedSource() {
        val output = SandboxExecution.run("for i = 1, 70000 do print('x') end")
        val source = SandboxExecution.run(" ".repeat(128 * 1024 + 1))

        assertTrue(output.ok)
        assertTrue(output.output.contains("output truncated"))
        assertFalse(source.ok)
        assertTrue(source.error.contains("source exceeds"))
    }

    @Test
    fun executionBoundsRuntimeErrorsForIpc() {
        val result = SandboxExecution.run("error(string.rep('x', 128 * 1024))")

        assertFalse(result.ok)
        assertTrue(result.error.contains("error truncated"))
        assertTrue(result.error.length <= 16 * 1024)
    }
}

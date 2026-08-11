package com.androlua

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class LuaSandboxTest {
    @Test
    fun syntaxCheckCompilesWithoutExecutingCode() {
        assertEquals(null, SandboxExecution.checkSyntax("error('must not run')"))
        assertTrue(SandboxExecution.checkSyntax("local value =") != null)
    }

    @Test
    fun executionUsesRestrictedGlobalsAndCapturesOutput() {
        val result = SandboxExecution.run(
            "print('safe'); assert(luajava == nil and io == nil and package == nil " +
                "and require == nil and debug == nil and type(http.request) == 'function')"
        )

        assertTrue(result.ok)
        assertEquals("safe", result.output.trim())
    }

    @Test
    fun executionRequiresExplicitPublicHttpsHosts() {
        val missingHost = SandboxExecution.run("return http.request('https://example.com')")
        val insecure = SandboxExecution.run(
            "return http.request('http://example.com')",
            setOf("example.com")
        )
        val privateHost = runCatching { SandboxHttp.parseAllowedHosts("localhost") }.exceptionOrNull()

        assertFalse(missingHost.ok)
        assertTrue(missingHost.error.contains("not authorized"))
        assertFalse(insecure.ok)
        assertTrue(insecure.error.contains("only allows HTTPS"))
        assertTrue(privateHost?.message.orEmpty().contains("not public"))
        assertEquals(
            setOf("example.com", "api.example.com"),
            SandboxHttp.parseAllowedHosts("EXAMPLE.COM.\napi.example.com")
        )
        assertTrue(runCatching { SandboxHttp.parseAllowedHosts("127.0.0.1") }.isFailure)
    }

    @Test
    fun networkPolicyRejectsPrivateAndReservedAddresses() {
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("127.0.0.1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("10.0.0.1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("169.254.169.254")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("192.88.99.2")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:db8::1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:2::1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:5::1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:10::1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:1::4")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("3fff::1")))
        assertFalse(SandboxHttp.isPublicAddress(InetAddress.getByName("64:ff9b::a00:1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("64:ff9b::101:101")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:1::1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:3::1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:4:112::1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("2001:20::1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("1.1.1.1")))
        assertTrue(SandboxHttp.isPublicAddress(InetAddress.getByName("2606:4700:4700::1111")))
    }

    @Test
    fun executionProvidesJsonCodecHashAndAssertions() {
        val result = SandboxExecution.run(
            """
            local value = json.decode('{"name":"Lua","items":[1,true,null],"empty":[]}')
            assert_equal(value.name, "Lua")
            assert_equal(value.items[1], 1)
            assert(value.items[3] == json.null)
            assert_equal(json.encode(value), '{"empty":[],"items":[1,true,null],"name":"Lua"}')
            assert_equal(json.encode(json.array()), '[]')
            assert_equal(codec.base64_decode(codec.base64_encode("hello")), "hello")
            assert_equal(codec.hex_decode(codec.hex_encode("A\0B")), "A\0B")
            assert_equal(codec.url_decode(codec.url_encode("a b/中")), "a b/中")
            assert_equal(hash.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            return { b = 2, a = 1 }, "ok"
            """.trimIndent()
        )

        assertTrue(result.error, result.ok)
        assertTrue(result.output.contains("[return] {a = 1, b = 2}, \"ok\""))
    }

    @Test
    fun executionRejectsUnsafeJsonAndReportsAssertionDiffs() {
        val cycle = SandboxExecution.run("local value = {}; value.self = value; return json.encode(value)")
        val duplicate = SandboxExecution.run("return json.decode('{\"a\":1,\"a\":2}')")
        val assertion = SandboxExecution.run("assert_equal({a = 1}, {a = 2}, 'mismatch')")

        assertFalse(cycle.ok)
        assertTrue(cycle.error.contains("cyclic"))
        assertFalse(duplicate.ok)
        assertTrue(duplicate.error.contains("duplicate object key"))
        assertFalse(assertion.ok)
        assertTrue(assertion.error.contains("mismatch"))
        assertTrue(assertion.error.contains("expected:"))
        assertTrue(assertion.error.contains("actual:"))
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

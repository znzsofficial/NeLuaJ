package com.nekolaska.test

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.luaj.lib.jse.JsePlatform

class LuaFunction1InteropTest {

    @Test
    fun testLuaFunctionPassedToKotlinFunction1() {
        val globals = JsePlatform.standardGlobals()
        val script = """
            local target = luajava.bindClass('com.nekolaska.test.KotlinDirectTest')
            local captured = nil
            local fn = function(str)
                captured = str
            end
            local ok, res = pcall(function()
                return target.executeKotlinDirect(fn)
            end)
            return ok, tostring(res), captured
        """.trimIndent()

        val results = globals.load(script).invoke()
        val ok = results.arg(1).toboolean()
        val res = results.arg(2).tojstring()
        val captured = results.arg(3).tojstring()

        println("Lua Interop Result - ok: $ok, res: $res, captured: $captured")
        assertTrue("Expected pcall to succeed but failed with: $res", ok)
        assertEquals("Hello from Real Kotlin", captured)
    }
}

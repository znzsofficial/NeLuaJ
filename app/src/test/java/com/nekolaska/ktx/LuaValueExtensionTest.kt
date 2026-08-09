package com.nekolaska.ktx

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.luaj.LuaValue
import org.luaj.lib.jse.JsePlatform

class LuaValueExtensionTest {
    @Test
    fun kotlinRequireUsesPackageLibraryInsteadOfOverriddenGlobal() {
        val globals = JsePlatform.standardGlobals()
        globals.load(
            "package.preload['ktx_require_test'] = function() return 41 end; " +
                "require = function() return 0 end"
        ).call()

        assertEquals(41, globals.require("ktx_require_test").toint())
    }

    @Test
    fun kotlinHelpersPreserveLuaArgumentsAndValues() {
        val function = JsePlatform.standardGlobals()
            .load("return function(first, second) return first + second end")
            .call()

        assertEquals(7, function.callLua(3, 4).toint())
        assertEquals(7, function.invokeLua(3, 4).arg1().toint())
        assertEquals(7, LuaValue.valueOf(7).requireJava<Int>())
        assertNull(LuaValue.NIL.toJavaOrNull<String>())

        val multiple = JsePlatform.standardGlobals().load("return function() return 1, nil, 'third' end").call()
        assertEquals(1, multiple.invokeLua().arg1().toint())
        assertEquals(1, multiple.callLua().toint())
        val nullableArgumentFunction = JsePlatform.standardGlobals()
            .load("return function(a, b, c) return a + c end")
            .call()
        assertEquals(3, nullableArgumentFunction.callLua(1, null, 2).toint())
    }

    @Test
    fun luaStringsUseUtf8AndExposeTheirActiveRange() {
        val value = "Lua and Kotlin".toLuaString().checkstring()

        assertArrayEquals("Lua and Kotlin".toByteArray(Charsets.UTF_8), value.bytes.copyOfRange(value.offset, value.offset + value.byteLength))
    }
}

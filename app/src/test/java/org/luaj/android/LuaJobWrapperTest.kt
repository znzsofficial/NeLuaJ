package org.luaj.android

import kotlinx.coroutines.Job
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.luaj.Globals
import org.luaj.lib.jse.CoerceJavaToLua
import org.luaj.lib.jse.JsePlatform

class LuaJobWrapperTest {
    @Test
    fun cancelCancelsAndReleasesTheJob() {
        val job = Job()
        val wrapper = LuaJobWrapper(job)
        val luaWrapper = CoerceJavaToLua.coerce(wrapper)

        assertTrue(wrapper.isActive())
        assertTrue(luaWrapper["job"].isuserdata(Job::class.java))
        val globals: Globals = JsePlatform.standardGlobals()
        globals.set("job", luaWrapper)
        val result = globals.load(
            "local active = job.isActive(); job.cancel(); return active, job.isActive(), job.job == nil"
        ).invoke()

        assertTrue(job.isCancelled)
        assertFalse(wrapper.isActive())
        assertTrue(wrapper.isGc())
        assertTrue(luaWrapper["job"].isnil())
        assertTrue(result.arg1().toboolean())
        assertFalse(result.arg(2).toboolean())
        assertTrue(result.arg(3).toboolean())
    }
}

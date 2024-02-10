package github.znzsofficial.utils

import org.luaj.LuaClosure
import org.luaj.LuaError
import org.luaj.compiler.DumpState
import org.luaj.lib.jse.JsePlatform
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.io.IOException

object CompileUtil {
    private val mGlobals = JsePlatform.standardGlobals()

    private fun getByteArray(path: String?): ByteArray {
        val checkfunction = mGlobals.loadfile(path).checkfunction(1) as LuaClosure
        val baos = ByteArrayOutputStream()
        return try {
            DumpState.dump(checkfunction.c, baos, true)
            baos.toByteArray()
        } catch (e: Exception) {
            throw LuaError(e)
        }
    }

    fun dump(input: String?, output: String?) {
        try {
            val fos = FileOutputStream(output)
            fos.write(getByteArray(input))
            fos.close()
        } catch (e: IOException) {
            throw LuaError(e)
        }
    }
}

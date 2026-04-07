package org.luaj.android

import com.nekolaska.ktx.finder
import com.nekolaska.ktx.m_bytes
import com.nekolaska.ktx.m_length
import com.nekolaska.ktx.m_offset
import org.luaj.Globals
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.OneArgFunction
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.LuajavaLib
import java.io.File
import java.io.FileOutputStream

/**
 * Created by nirenr on 2020/1/16.
 */
class file : TwoArgFunction() {
    private lateinit var mGlobals: Globals

    override fun call(modname: LuaValue?, env: LuaValue): LuaValue? {
        mGlobals = env.checkglobals()
        val pkg = env.get("package")
        if (!pkg.isnil()) {
            pkg.get("loaded").set("file", LuaTable().apply {
                set("readall", readall())
                set("list", list())
                set("exists", exists())
                set("save", save())
                set("type", _type())
                set("info", info())
                set("mkdir", mkdir())
                env.set("file", this@apply)
            })
        }
        return NIL
    }

    private inner class readall : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return try {
                LuaString.valueOf(readAll(mGlobals.finder.findFile(arg.tojstring())))
            } catch (_: Exception) {
                NIL
            }
        }
    }

    private inner class list : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return LuajavaLib.asTable(list(mGlobals.finder.findFile(arg.tojstring())))
        }
    }

    private inner class _type : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            val path = mGlobals.finder.findFile(arg.tojstring()) ?: arg.tojstring()
            return valueOf(if (File(path).isDirectory) "dir" else "file")
        }
    }

    private inner class info : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue {
            val pathStr = arg.tojstring()
            val resolvedPath = mGlobals.finder.findFile(pathStr) ?: pathStr
            val f = File(resolvedPath)
            
            val ret = LuaTable()
            if (!f.exists()) {
                ret.jset("type", "")
            } else {
                ret.jset("type", if (f.isDirectory) "dir" else "file")
            }
            ret.jset("path", f.absolutePath)
            ret.jset("size", f.length())
            ret.jset("name", f.name)
            ret.jset("parent", f.parent)
            ret.jset("read", f.canRead())
            ret.jset("write", f.canWrite())
            return ret
        }
    }

    private inner class mkdir : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            val path = mGlobals.finder.findFile(arg.tojstring()) ?: arg.tojstring()
            return valueOf(File(path).mkdirs())
        }
    }

    private inner class exists : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return try {
                valueOf(exists(mGlobals.finder.findFile(arg.tojstring())))
            } catch (_: Exception) {
                NIL
            }
        }
    }

    private inner class save : TwoArgFunction() {
        override fun call(arg1: LuaValue, arg2: LuaValue): LuaValue? {
            return valueOf(
                save(
                    mGlobals.finder.findFile(arg1.tojstring()),
                    arg2.checkstring()
                )
            )
        }
    }

    companion object {
        fun readAll(path: String): String {
            return File(path).readText()
        }


        fun list(path: String): Array<String?>? {
            return File(path).list()
        }

        fun exists(path: String): Boolean {
            return File(path).exists()
        }

        fun save(path: String?, text: LuaString): Boolean {
            if (path == null) return false
            return try {
                File(path).parentFile?.mkdirs()
                FileOutputStream(path).use { fos ->
                    fos.write(text.m_bytes, text.m_offset, text.m_length)
                }
                true
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }
    }
}

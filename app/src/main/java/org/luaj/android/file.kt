package org.luaj.android

import com.nekolaska.ktx.byteLength
import com.nekolaska.ktx.bytes
import com.nekolaska.ktx.offset
import com.nekolaska.ktx.resourceFinder
import org.luaj.Globals
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import com.nekolaska.io.AtomicFile
import org.luaj.lib.OneArgFunction
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.LuajavaLib
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes
import java.util.Base64

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
                set("readbinary", readbinary())
                set("savebinary", savebinary())
                set("renameexclusive", renameexclusive())
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
                LuaString.valueOf(readAll(mGlobals.resourceFinder.findFile(arg.tojstring())))
            } catch (_: Exception) {
                NIL
            }
        }
    }

    private inner class list : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return LuajavaLib.asTable(list(mGlobals.resourceFinder.findFile(arg.tojstring())))
        }
    }

    private inner class _type : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            val path = mGlobals.resourceFinder.findFile(arg.tojstring()) ?: arg.tojstring()
            return try {
                pathType(path)?.let { valueOf(it) } ?: NIL
            } catch (error: Exception) {
                throw org.luaj.LuaError(error.toString())
            }
        }
    }

    // JSON-safe byte snapshots; readall deliberately keeps its public UTF-8 semantics.
    private inner class readbinary : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs = try {
            val path = mGlobals.resourceFinder.findFile(args.arg1().checkjstring()) ?: args.arg1().checkjstring()
            valueOf(readBinary(path))
        } catch (error: Exception) {
            varargsOf(arrayOf(NIL, valueOf(error.toString())))
        }
    }

    private inner class savebinary : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs = try {
            val path = mGlobals.resourceFinder.findFile(args.arg1().checkjstring()) ?: args.arg1().checkjstring()
            saveBinary(path, args.arg(2).checkjstring())
            TRUE
        } catch (error: Exception) {
            varargsOf(arrayOf(FALSE, valueOf(error.toString())))
        }
    }

    private inner class renameexclusive : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs = try {
            // No REPLACE_EXISTING: both files and directories refuse an occupied target.
            renameExclusive(args.arg1().checkjstring(), args.arg(2).checkjstring())
            TRUE
        } catch (error: Exception) {
            varargsOf(arrayOf(FALSE, valueOf(error.toString())))
        }
    }

    private inner class info : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue {
            val pathStr = arg.tojstring()
            val resolvedPath = mGlobals.resourceFinder.findFile(pathStr) ?: pathStr
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
            val path = mGlobals.resourceFinder.findFile(arg.tojstring()) ?: arg.tojstring()
            return valueOf(File(path).mkdirs())
        }
    }

    private inner class exists : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue? {
            return try {
                valueOf(exists(mGlobals.resourceFinder.findFile(arg.tojstring())))
            } catch (_: Exception) {
                NIL
            }
        }
    }

    private inner class save : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            return try {
                val path = mGlobals.resourceFinder.findFile(args.arg1().checkjstring())
                    ?: throw java.io.IOException("Cannot resolve file path: ${args.arg1()}")
                saveOrThrow(path, args.arg(2).checkstring())
                TRUE
            } catch (error: Exception) {
                varargsOf(arrayOf(FALSE, valueOf(error.toString())))
            }
        }
    }

    companion object {
        fun renameExclusive(source: String, target: String) {
            if (pathType(target) != null) throw java.nio.file.FileAlreadyExistsException(target)
            Files.move(File(source).toPath(), File(target).toPath())
        }

        fun pathType(path: String): String? {
            val attrs = try {
                Files.readAttributes(File(path).toPath(), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
            } catch (_: NoSuchFileException) {
                // Some providers (notably Windows) also report ENOTDIR as missing.
                // Only a genuinely missing descendant may become a missing snapshot.
                var parent = File(path).toPath().toAbsolutePath().parent
                while (parent != null) {
                    try {
                        val ancestor = Files.readAttributes(parent, BasicFileAttributes::class.java)
                        if (!ancestor.isDirectory) throw java.nio.file.NotDirectoryException(parent.toString())
                        break
                    } catch (_: NoSuchFileException) {
                        parent = parent.parent
                    }
                }
                return null
            }
            return when {
                attrs.isDirectory -> "dir"
                attrs.isRegularFile -> "file"
                else -> throw java.io.IOException("Unsupported file type: $path")
            }
        }

        fun readBinary(path: String): String = Base64.getEncoder().encodeToString(File(path).readBytes())

        fun saveBinary(path: String, encoded: String) {
            AtomicFile.replaceBytesOrThrow(path, Base64.getDecoder().decode(encoded))
        }

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
                saveOrThrow(path, text)
                true
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }

        private fun saveOrThrow(path: String, text: LuaString) {
            AtomicFile.replaceBytesOrThrow(path, text.bytes.copyOfRange(text.offset, text.offset + text.byteLength))
        }
    }
}

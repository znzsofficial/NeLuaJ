package com.nekolaska.io

import com.androlua.LuaUtil
import net.lingala.zip4j.ZipFile
import okio.buffer
import okio.sink
import okio.source
import org.luaj.LuaTable
import org.luaj.lib.jse.JsePlatform
import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import kotlin.concurrent.thread

object LuaFileUtil {
    val impl =
        if (runCatching { Class.forName("java.nio.file.Files") }.isSuccess) NioImpl() else OkioImpl()

    fun create(path: String, content: String) {
        impl.create(path)
        impl.write(path, content)
    }

    fun write(path: String, content: String): Boolean {
        return write(path, content, File(path))
    }

    fun write(path: String, content: String, file: File): Boolean {
        if (!file.exists()) return false
        return impl.write(path, content)
    }

    fun read(path: String): String {
        return impl.read(path)
    }

    fun remove(path: String): Boolean {
        return impl.remove(path)
    }

    fun rename(oldPath: String, newPath: String): Boolean {
        return impl.rename(oldPath, newPath)
    }

    fun checkDirectory(path: String) {
        return impl.checkDirectory(path)
    }

    fun extract(zipPath: String, outPath: String) {
        thread {
            ZipFile(zipPath).extractAll(outPath)
        }
    }

    fun compress(srcFolderPath: String, destZipFilePath: String, fileName: String) {
        LuaUtil.zip(srcFolderPath, destZipFilePath, fileName)
    }

    fun loadLua(path: String) = JsePlatform.standardGlobals().apply {
        loadfile(path).call()
    } as LuaTable

    fun moveDirectory(src: String, dest: String) {
        if (File(src).isDirectory) {
            File(dest).mkdirs()
            File(src).listFiles()?.forEach {
                moveDirectory(it.absolutePath, dest + File.separator + it.name)
            }
        } else {
            File(dest).parentFile?.mkdirs()
            File(src).renameTo(File(dest))
        }
    }

    interface Impl {
        fun write(path: String, content: String): Boolean
        fun read(path: String): String
        fun remove(path: String): Boolean
        fun checkDirectory(path: String)
        fun rename(oldPath: String, newPath: String): Boolean
        fun create(path: String)
    }

    class NioImpl : Impl {
        override fun read(path: String): String {
            return try {
                String(Files.readAllBytes(Paths.get(path)), Charsets.UTF_8)
            } catch (e: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String): Boolean {
            return try {
                Files.write(Paths.get(path), content.toByteArray(Charsets.UTF_8))
                true
            } catch (e: Exception) {
                false
            }
        }

        override fun remove(path: String): Boolean {
            return try {
                Files.delete(Paths.get(path))
                true
            } catch (e: Exception) {
                false
            }
        }

        override fun checkDirectory(path: String) {
            val tmpPath = Paths.get(path)
            if (!Files.isDirectory(tmpPath)) {
                Files.createDirectories(tmpPath)
            }
        }

        override fun rename(oldPath: String, newPath: String): Boolean {
            return try {
                Files.move(Paths.get(oldPath), Paths.get(newPath))
                true
            } catch (e: Exception) {
                false
            }
        }

        override fun create(path: String) {
            Paths.get(path).let {
                if (!Files.exists(it)) Files.createFile(it)
            }
        }
    }

    class OkioImpl : Impl {
        override fun read(path: String): String {
            return try {
                File(path).source().buffer().readUtf8()
            } catch (e: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String): Boolean {
            return try {
                File(path).sink().buffer().apply {
                    writeUtf8(content)
                    close()
                }
                true
            } catch (e: Exception) {
                false
            }
        }

        override fun remove(path: String): Boolean {
            return File(path).delete()
        }

        override fun checkDirectory(path: String) {
            val file = File(path)
            if (!file.exists()) {
                file.mkdirs()
            }
        }

        override fun rename(oldPath: String, newPath: String): Boolean {
            return File(oldPath).renameTo(File(newPath))
        }

        override fun create(path: String) {
            File(path).apply {
                if (!exists()) createNewFile()
            }
        }
    }
}
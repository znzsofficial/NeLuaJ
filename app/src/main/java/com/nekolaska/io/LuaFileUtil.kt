package com.nekolaska.io

import com.androlua.LuaUtil
import net.lingala.zip4j.ZipFile
import okio.buffer
import okio.sink
import okio.source
import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import kotlin.concurrent.thread

object LuaFileUtil {
    private val hasNio by lazy {
        try {
            Class.forName("java.nio.file.Files")
            true
        } catch (e: ClassNotFoundException) {
            false
        }
    }
    val impl = if (hasNio) NioImpl() else OkioImpl()
    fun create(path: String, content: String) {
        val file = File(path)
        if (!file.exists()) {
            file.createNewFile()
        }
        write(path, content, file)
    }

    fun write(path: String, content: String): Boolean {
        return write(path, content, File(path))
    }

    fun write(path: String, content: String, file: File): Boolean {
        if (!file.exists()) return false
        return impl.write(path, content, file)
    }

    fun read(path: String): String {
        return impl.read(path)
    }

    fun extract(zipPath: String, outPath: String) {
        thread {
            ZipFile(zipPath).extractAll(outPath)
        }
    }

    fun compress(srcFolderPath: String, destZipFilePath: String, fileName: String) {
        LuaUtil.zip(srcFolderPath, destZipFilePath, fileName)
    }

    fun remove(path: String): Boolean {
        return File(path).delete()
    }

    fun rename(oldPath: String, newPath: String): Boolean {
        return File(oldPath).renameTo(File(newPath))
    }

    fun checkDirectory(path: String) {
        val file = File(path)
        if (!file.exists()) {
            file.mkdirs()
        }
    }

    interface Impl {
        fun write(path: String, content: String, file: File): Boolean
        fun read(path: String): String
    }

    class NioImpl : Impl {
        override fun read(path: String): String {
            return try {
                String(Files.readAllBytes(Paths.get(path)), Charsets.UTF_8)
            } catch (e: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String, file: File): Boolean {
            return try {
                Files.write(Paths.get(path), content.toByteArray(Charsets.UTF_8))
                true
            } catch (e: Exception) {
                false
            }
        }
    }

    class OkioImpl : Impl {
        override fun read(path: String): String {
            return try {
                val source = File(path).source().buffer()
                source.readUtf8()
            } catch (e: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String, file: File): Boolean {
            return try {
                val sink = File(path).sink().buffer()
                sink.writeUtf8(content)
                sink.close()
                true
            } catch (e: Exception) {
                false
            }
        }
    }
}
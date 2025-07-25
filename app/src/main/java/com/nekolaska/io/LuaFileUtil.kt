package com.nekolaska.io

import com.androlua.LuaUtil
import com.nekolaska.ktx.toLuaValue
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.progress.ProgressMonitor
import okio.buffer
import okio.sink
import okio.source
import org.luaj.LuaFunction
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

    fun extract(inFile: File, targetDir: File, callback: LuaFunction) {
        require(inFile.exists() && inFile.isFile) { "Invalid zip file: ${inFile.absolutePath}" }
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalArgumentException("Failed to create target directory: ${targetDir.absolutePath}")
        }

        try {
            val zipFile = ZipFile(inFile)
            val totalSize = inFile.length() // ZIP 文件总大小
            val monitor = zipFile.progressMonitor

            zipFile.isRunInThread = true // 允许异步执行
            zipFile.extractAll(targetDir.absolutePath)

            thread {
                while (monitor.state != ProgressMonitor.State.READY) {
                    callback.call(monitor.workCompleted.toLuaValue(), totalSize.toLuaValue())
                    Thread.sleep(100) // 避免 CPU 负担过重
                }
                // 解压完成，确保回调 100% 进度
                callback.call(totalSize.toLuaValue(), totalSize.toLuaValue())
            }
        } catch (e: Exception) {
            throw RuntimeException("Failed to unzip file: ${e.message}", e)
        }
    }

    fun compress(srcFolderPath: String, destZipFilePath: String, fileName: String) {
        LuaUtil.zip(srcFolderPath, destZipFilePath, fileName)
    }

    fun loadLua(path: String) = JsePlatform.standardGlobals().apply {
        loadfile(path).call()
    } as LuaTable

    fun moveDirectory(src: String, dest: String): Boolean {
        return try {
            val srcFile = File(src)
            val destFile = File(dest)
            srcFile.copyRecursively(destFile, overwrite = true)
            srcFile.deleteRecursively()
            true
        } catch (_: Exception) {
            false
        }
    }

    fun isEmpty(path: String) = File(path).listFiles()?.isEmpty() == true

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
            } catch (_: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String): Boolean {
            return try {
                Files.write(Paths.get(path), content.toByteArray(Charsets.UTF_8))
                true
            } catch (_: Exception) {
                false
            }
        }

        override fun remove(path: String): Boolean {
            return try {
                Files.delete(Paths.get(path))
                true
            } catch (_: Exception) {
                false
            }
        }

        override fun checkDirectory(path: String) {
            Paths.get(path).let {
                if (!Files.exists(it)) {
                    Files.createDirectories(it)
                }
            }
        }

        override fun rename(oldPath: String, newPath: String): Boolean {
            return try {
                Files.move(Paths.get(oldPath), Paths.get(newPath))
                true
            } catch (_: Exception) {
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
            } catch (_: Exception) {
                ""
            }
        }

        override fun write(path: String, content: String): Boolean {
            return try {
                File(path).sink().buffer().use {
                    it.writeUtf8(content)
                }
                true
            } catch (_: Exception) {
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
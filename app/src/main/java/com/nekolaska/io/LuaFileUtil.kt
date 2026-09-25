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
        ensureParent(path)
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

    /**
     * 写入文件；不存在则创建（含父目录）。
     * 解决 write() 在文件不存在时直接返回 false 的问题。
     */
    fun writeOrCreate(path: String, content: String): Boolean {
        return try {
            ensureParent(path)
            val file = File(path)
            if (!file.exists()) {
                impl.create(path)
            }
            impl.write(path, content)
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureParent(path: String) {
        val parent = File(path).parentFile ?: return
        if (!parent.exists()) {
            parent.mkdirs()
        }
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

    /**
     * 目录条目元信息：一次返回 name/isDir/mtime/size。
     * Lua 侧拿到的直接是 LuaTable 数组，免去逐项构造 File 对象与多次 JNI 往返。
     */
    fun listMeta(path: String): LuaTable {
        val result = LuaTable()
        val files = File(path).listFiles() ?: return result
        var index = 1
        for (f in files) {
            val entry = LuaTable()
            entry.set("name", f.name.toLuaValue())
            entry.set("isDir", f.isDirectory.toLuaValue())
            entry.set("mtime", f.lastModified().toLuaValue())
            entry.set("size", f.length().toLuaValue())
            result.set(index, entry)
            index++
        }
        return result
    }

    /** 只列子目录名，按最近修改优先。 */
    fun listDirs(path: String): LuaTable {
        val result = LuaTable()
        val dirs = File(path).listFiles()?.filter { it.isDirectory } ?: return result
        var index = 1
        for (f in dirs.sortedByDescending { it.lastModified() }) {
            result.set(index, f.name.toLuaValue())
            index++
        }
        return result
    }

    /** 最近修改时间（毫秒）；不存在返回 0。 */
    fun lastModified(path: String): Long =
        File(path).takeIf { it.exists() }?.lastModified() ?: 0L

    private val SKIP_DIRS = setOf(
        ".git", ".svn", ".hg", ".idea", ".gradle", "build", "dist",
        "target", "node_modules", "bin", "obj", ".cxx"
    )

    /**
     * 递归列出目录树，返回相对路径数组（目录带 / 后缀，逐层按名称排序）。
     * [filter] 为空白时不过滤；跳过版本控制与构建目录。
     */
    fun listTree(path: String, filter: String, maxItems: Int, maxDepth: Int): LuaTable {
        val result = LuaTable()
        val root = File(path)
        if (!root.isDirectory) return result
        val flt = (filter ?: "").trim()
        var count = 0

        fun walk(dir: File, prefix: String, depth: Int) {
            if (count >= maxItems || depth > maxDepth) return
            val entries = dir.listFiles() ?: return
            for (f in entries.sortedBy { it.name }) {
                if (count >= maxItems) return
                val rel = prefix + f.name + (if (f.isDirectory) "/" else "")
                if (flt.isEmpty() || rel.contains(flt) || f.name.contains(flt)) {
                    count++
                    result.set(count, rel.toLuaValue())
                }
                if (f.isDirectory && f.name !in SKIP_DIRS) {
                    walk(f, rel, depth + 1)
                }
            }
        }
        walk(root, "", 0)
        return result
    }

    /**
     * 在目录树内做文本搜索（子串匹配，非正则）。
     * 返回 { matches = { "路径:行号: 内容" }, scanned = 已扫描文件数 }。
     * 跳过版本控制与构建目录、超过 [maxFileKB] 的文件与二进制文件（NUL 检测）。
     */
    fun searchInFiles(
        root: String,
        pattern: String,
        ignoreCase: Boolean,
        maxResults: Int,
        maxFileKB: Int
    ): LuaTable {
        val result = LuaTable()
        val matches = LuaTable()
        result.set("matches", matches)
        result.set("scanned", 0.toLuaValue())
        val rootDir = File(root)
        if (pattern.isEmpty() || !rootDir.isDirectory) return result
        var scanned = 0
        var found = 0
        val maxBytes = maxFileKB.coerceAtLeast(1) * 1024L
        val maxScanFiles = 2000
        val maxDepth = 8

        fun walk(dir: File, depth: Int) {
            if (found >= maxResults || scanned >= maxScanFiles || depth > maxDepth) return
            val entries = dir.listFiles() ?: return
            for (f in entries.sortedBy { it.name }) {
                if (found >= maxResults || scanned >= maxScanFiles) return
                if (f.isDirectory) {
                    if (f.name !in SKIP_DIRS) walk(f, depth + 1)
                    continue
                }
                scanned++
                val length = f.length()
                if (length <= 0 || length > maxBytes) continue
                try {
                    val bytes = f.readBytes()
                    // 二进制嗅探：含 NUL 跳过（与原 Lua 实现一致）
                    var binary = false
                    for (b in bytes) {
                        if (b == 0.toByte()) {
                            binary = true
                            break
                        }
                    }
                    if (binary) continue
                    val content = String(bytes, Charsets.UTF_8)
                    var lineno = 0
                    for (line in content.lineSequence()) {
                        lineno++
                        val hit = if (ignoreCase) {
                            line.contains(pattern, ignoreCase = true)
                        } else {
                            line.contains(pattern)
                        }
                        if (hit) {
                            found++
                            matches.set(found, (f.path + ":" + lineno + ": " + line).toLuaValue())
                            if (found >= maxResults) return
                        }
                    }
                } catch (_: Exception) {
                    // 单个文件读取/解码失败不影响整体搜索
                }
            }
        }
        walk(rootDir, 0)
        result.set("matches", matches)
        result.set("scanned", scanned.toLuaValue())
        return result
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
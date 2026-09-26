package com.nekolaska.io

import com.androlua.LuaUtil
import com.nekolaska.ktx.toLuaValue
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.progress.ProgressMonitor
import org.luaj.LuaFunction
import org.luaj.LuaTable
import org.luaj.lib.jse.JsePlatform
import java.io.File
import java.util.Comparator
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import kotlin.concurrent.thread

object LuaFileUtil {
    fun create(path: String, content: String) {
        ensureParent(path)
        val p = Paths.get(path)
        if (!Files.exists(p)) Files.createFile(p)
        Files.write(p, content.toByteArray(Charsets.UTF_8))
    }

    fun write(path: String, content: String): Boolean {
        return write(path, content, File(path))
    }

    fun write(path: String, content: String, file: File): Boolean {
        if (!file.exists()) return false
        return try {
            Files.write(file.toPath(), content.toByteArray(Charsets.UTF_8))
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 写入文件；不存在则创建（含父目录）。
     * 解决 write() 在文件不存在时直接返回 false 的问题。
     */
    fun writeOrCreate(path: String, content: String): Boolean {
        return try {
            ensureParent(path)
            val p = Paths.get(path)
            if (!Files.exists(p)) Files.createFile(p)
            Files.write(p, content.toByteArray(Charsets.UTF_8))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureParent(path: String) {
        val parent = Paths.get(path).parent ?: return
        if (!Files.exists(parent)) Files.createDirectories(parent)
    }

    fun read(path: String): String {
        return try {
            String(Files.readAllBytes(Paths.get(path)), Charsets.UTF_8)
        } catch (_: Exception) {
            ""
        }
    }

    fun remove(path: String): Boolean {
        return try {
            Files.delete(Paths.get(path))
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 递归删除文件或目录。路径不存在视为已成功。
     * 子项列举失败，或任一子项删不掉时返回 false，且不会假装父目录已经删掉。
     */
    fun removeTree(path: String): Boolean {
        val root = Paths.get(path)
        if (!Files.exists(root)) return true
        return try {
            // 先收齐再删。边遍历边删时，目录流还开着，部分机上会漏删或抛错。
            val ordered = Files.walk(root).use { stream ->
                stream.sorted(Comparator.reverseOrder()).toList()
            }
            for (child in ordered) {
                Files.delete(child)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 复制单个文件。目标父目录不存在时创建。源不是文件、或源和目标是同一路径时返回 false。 */
    fun copyFile(src: String, dest: String): Boolean {
        return try {
            val input = Paths.get(src)
            if (!Files.isRegularFile(input)) return false
            val output = Paths.get(dest)
            if (samePath(input, output)) return false
            output.parent?.let { Files.createDirectories(it) }
            Files.copy(input, output, StandardCopyOption.REPLACE_EXISTING)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 递归复制文件或目录，不删除源。
     * 目标落在源目录内部时拒绝，避免复制到自己里面无限递归。
     */
    fun copyTree(src: String, dest: String): Boolean {
        return try {
            val source = Paths.get(src)
            if (!Files.exists(source)) return false
            val target = Paths.get(dest)
            val srcAbs = source.toAbsolutePath().normalize()
            val destAbs = target.toAbsolutePath().normalize()
            // Path.startsWith 按路径段比较，不会把 /proj 误判成 /proj2 的前缀
            if (destAbs == srcAbs || destAbs.startsWith(srcAbs)) return false
            Files.walk(source).use { stream ->
                for (child in stream) {
                    val out = target.resolve(source.relativize(child))
                    if (Files.isDirectory(child)) {
                        Files.createDirectories(out)
                    } else {
                        out.parent?.let { Files.createDirectories(it) }
                        Files.copy(child, out, StandardCopyOption.REPLACE_EXISTING)
                    }
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun samePath(a: Path, b: Path): Boolean {
        return a.toAbsolutePath().normalize() == b.toAbsolutePath().normalize()
    }

    fun rename(oldPath: String, newPath: String): Boolean {
        return try {
            Files.move(Paths.get(oldPath), Paths.get(newPath))
            true
        } catch (_: Exception) {
            false
        }
    }

    fun checkDirectory(path: String) {
        val p = Paths.get(path)
        if (!Files.exists(p)) Files.createDirectories(p)
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
        if (!copyTree(src, dest)) return false
        return removeTree(src)
    }

    fun isEmpty(path: String): Boolean {
        val p = Paths.get(path)
        if (!Files.isDirectory(p)) return false
        return Files.newDirectoryStream(p).use { !it.iterator().hasNext() }
    }

    /**
     * 目录条目元信息：一次返回 name/isDir/mtime/size。
     * Lua 侧拿到的直接是 LuaTable 数组，免去逐项构造 File 对象与多次 JNI 往返。
     */
    fun listMeta(path: String): LuaTable {
        val result = LuaTable()
        val dir = Paths.get(path)
        if (!Files.isDirectory(dir)) return result
        Files.newDirectoryStream(dir).use { stream ->
            var index = 1
            for (child in stream) {
                try {
                    val attrs = Files.readAttributes(child, BasicFileAttributes::class.java)
                    val entry = LuaTable()
                    entry.set("name", child.fileName.toString().toLuaValue())
                    entry.set("isDir", attrs.isDirectory.toLuaValue())
                    entry.set("mtime", attrs.lastModifiedTime().toMillis().toLuaValue())
                    entry.set("size", attrs.size().toLuaValue())
                    result.set(index, entry)
                    index++
                } catch (_: Exception) {
                    // 单个条目读属性失败时跳过，不让整次列举失败
                }
            }
        }
        return result
    }

    /** 只列子目录名，按最近修改优先。 */
    fun listDirs(path: String): LuaTable {
        val result = LuaTable()
        val dir = Paths.get(path)
        if (!Files.isDirectory(dir)) return result
        val dirs = Files.newDirectoryStream(dir).use { stream ->
            stream.filter { Files.isDirectory(it) }
                .sortedByDescending { Files.getLastModifiedTime(it).toMillis() }
                .toList()
        }
        var index = 1
        for (child in dirs) {
            result.set(index, child.fileName.toString().toLuaValue())
            index++
        }
        return result
    }

    /** 最近修改时间（毫秒）；不存在返回 0。 */
    fun lastModified(path: String): Long {
        val p = Paths.get(path)
        if (!Files.exists(p)) return 0L
        return try {
            Files.getLastModifiedTime(p).toMillis()
        } catch (_: Exception) {
            0L
        }
    }

    private val SKIP_DIRS = setOf(
        ".git", ".svn", ".hg", ".idea", ".gradle", "build", "dist",
        "target", "node_modules", "bin", "obj", ".cxx"
    )

    /**
     * 递归列出目录树，返回相对路径数组（目录带 / 后缀，逐层按名称排序）。
     * [filter] 为空白时不过滤；跳过版本控制与构建目录。
     */
    fun listTree(path: String, filter: String?, maxItems: Int, maxDepth: Int): LuaTable {
        val result = LuaTable()
        val root = Paths.get(path)
        if (!Files.isDirectory(root)) return result
        val flt = (filter ?: "").trim()
        var count = 0

        fun walk(dir: Path, prefix: String, depth: Int) {
            if (count >= maxItems || depth > maxDepth) return
            val entries = Files.newDirectoryStream(dir).use { it.toList() }
                .sortedBy { it.fileName.toString() }
            for (child in entries) {
                if (count >= maxItems) return
                val name = child.fileName.toString()
                val isDir = Files.isDirectory(child)
                val rel = prefix + name + (if (isDir) "/" else "")
                if (flt.isEmpty() || rel.contains(flt) || name.contains(flt)) {
                    count++
                    result.set(count, rel.toLuaValue())
                }
                if (isDir && name !in SKIP_DIRS) {
                    walk(child, rel, depth + 1)
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
        val rootDir = Paths.get(root)
        if (pattern.isEmpty() || !Files.isDirectory(rootDir)) return result
        var scanned = 0
        var found = 0
        val maxBytes = maxFileKB.coerceAtLeast(1) * 1024L
        val maxScanFiles = 2000
        val maxDepth = 8

        fun walk(dir: Path, depth: Int) {
            if (found >= maxResults || scanned >= maxScanFiles || depth > maxDepth) return
            val entries = Files.newDirectoryStream(dir).use { it.toList() }
                .sortedBy { it.fileName.toString() }
            for (child in entries) {
                if (found >= maxResults || scanned >= maxScanFiles) return
                val name = child.fileName.toString()
                if (Files.isDirectory(child)) {
                    if (name !in SKIP_DIRS) walk(child, depth + 1)
                    continue
                }
                scanned++
                val length = Files.size(child)
                if (length <= 0 || length > maxBytes) continue
                try {
                    val bytes = Files.readAllBytes(child)
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
                            matches.set(found, (child.toAbsolutePath().toString() + ":" + lineno + ": " + line).toLuaValue())
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
}
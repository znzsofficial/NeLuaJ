package com.nekolaska.io

import com.androlua.LuaUtil
import com.nekolaska.ktx.toLuaValue
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.progress.ProgressMonitor
import org.luaj.LuaFunction
import org.luaj.LuaTable
import org.luaj.lib.jse.JsePlatform
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import kotlin.concurrent.thread
import kotlin.io.path.copyTo
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.fileSize
import kotlin.io.path.getLastModifiedTime
import kotlin.io.path.isDirectory
import kotlin.io.path.isRegularFile
import kotlin.io.path.readAttributes
import kotlin.io.path.readText
import kotlin.io.path.writeText
import kotlin.streams.asSequence
import kotlin.streams.toList as toKotlinList

object LuaFileUtil {
    fun create(path: String, content: String) {
        ensureParent(path)
        Paths.get(path).writeText(content)
    }

    fun write(path: String, content: String): Boolean {
        return write(path, content, File(path))
    }

    fun write(path: String, content: String, file: File): Boolean {
        if (!file.exists()) return false
        return try {
            file.toPath().writeText(content)
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
            Paths.get(path).writeText(content)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureParent(path: String) {
        val parent = Paths.get(path).parent ?: return
        if (!parent.exists()) parent.createDirectories()
    }

    fun read(path: String): String {
        return try {
            Paths.get(path).readText()
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
        // 不跟随链接。悬空符号链接本身还在，不能当成「路径不存在」。
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) return true
        return try {
            // 用 Kotlin 的 Stream.toList()，不要用同名的 Java 成员：
            // 成员方法优先于扩展，直接写 toList() 会编成 API 34 才有的 Stream.toList()。
            // 深度大的先删，子文件一定比父目录先去掉。
            val ordered = Files.walk(root).use { it.toKotlinList() }
                .sortedByDescending { it.nameCount }
            for (child in ordered) {
                Files.deleteIfExists(child)
            }
            !Files.exists(root, LinkOption.NOFOLLOW_LINKS)
        } catch (_: Exception) {
            false
        }
    }

    /** 复制单个文件。目标父目录不存在时创建。源不是文件、或源和目标是同一路径时返回 false。 */
    fun copyFile(src: String, dest: String): Boolean {
        return try {
            val input = Paths.get(src)
            if (!input.isRegularFile()) return false
            val output = Paths.get(dest)
            if (samePath(input, output)) return false
            output.parent?.createDirectories()
            input.copyTo(output, overwrite = true)
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
            if (!Files.exists(source, LinkOption.NOFOLLOW_LINKS)) return false
            val target = Paths.get(dest)
            // 用真实路径比较。只看绝对路径时，/sdcard 和 /storage/emulated/0 对不上，
            // 复制到自己内部的检查会漏掉。
            if (isSameOrInside(source, target)) return false
            Files.walk(source).use { stream ->
                stream.asSequence().forEach { child ->
                    val out = target.resolve(source.relativize(child))
                    // walk 默认不进入符号链接。isDirectory() 却会跟着链接走，
                    // 指向目录的链接会被建成一个空目录。这里两边都不跟随。
                    if (Files.isDirectory(child, LinkOption.NOFOLLOW_LINKS)) {
                        out.createDirectories()
                    } else {
                        out.parent?.createDirectories()
                        Files.copy(
                            child,
                            out,
                            StandardCopyOption.REPLACE_EXISTING,
                            LinkOption.NOFOLLOW_LINKS
                        )
                    }
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun samePath(a: Path, b: Path): Boolean {
        val left = canonical(a) ?: return true
        val right = canonical(b) ?: return true
        return left == right
    }

    /** 目标就是源，或落在源里面。解析不了真实路径时视为不安全，调用方应拒绝复制。 */
    private fun isSameOrInside(parent: Path, child: Path): Boolean {
        val base = canonical(parent) ?: return true
        val other = canonical(child) ?: return true
        return other == base || other.startsWith(base)
    }

    /**
     * 已存在的前缀用 toRealPath() 展开符号链接，后面尚未创建的部分再接回去。
     * 这样「目标还不存在」时也能和源的真实路径比较。
     */
    private fun canonical(path: Path): Path? {
        // 不能先 normalize()。link/.. 会被词法直接折掉，和内核「先跟链接再处理 ..」不一致，
        // 复制进自身的检查就能被绕开。
        val absolute = path.toAbsolutePath()
        val pending = ArrayList<String>()
        var current = absolute
        while (true) {
            if (Files.exists(current, LinkOption.NOFOLLOW_LINKS)) {
                val real = try {
                    current.toRealPath()
                } catch (_: Exception) {
                    // 悬空链接本身还在。后面没有剩余路径时，它的位置就是这个目录项。
                    // 后面还有 .. 或其他分量时，无法证明落点，交给调用方拒绝。
                    if (pending.isNotEmpty()) return null
                    current.toAbsolutePath()
                }
                var resolved = real
                for (name in pending.asReversed()) {
                    resolved = resolved.resolve(name)
                }
                return resolved.normalize()
            }
            val name = current.fileName?.toString() ?: return null
            pending.add(name)
            current = current.parent ?: return null
        }
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
        if (!p.exists()) p.createDirectories()
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
        if (!p.isDirectory()) return false
        return try {
            // 不要在 forEachDirectoryEntry 里 return：那是内联 lambda 的非局部返回，
            // 读目录失败时也会直接把异常抛出去。
            Files.newDirectoryStream(p).use { stream -> !stream.iterator().hasNext() }
        } catch (_: Exception) {
            false
        }
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
                    val attrs = child.readAttributes<BasicFileAttributes>()
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
            stream.filter { it.isDirectory() }
                .sortedByDescending { it.getLastModifiedTime().toMillis() }
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
        if (!p.exists()) return 0L
        return try {
            p.getLastModifiedTime().toMillis()
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
        if (!root.isDirectory()) return result
        val flt = (filter ?: "").trim()
        var count = 0

        fun walk(dir: Path, prefix: String, depth: Int) {
            if (count >= maxItems || depth > maxDepth) return
            val entries = Files.newDirectoryStream(dir).use { it.toList() }
                .sortedBy { it.fileName.toString() }
            for (child in entries) {
                if (count >= maxItems) return
                val name = child.fileName.toString()
                val isDir = child.isDirectory()
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
        if (pattern.isEmpty() || !rootDir.isDirectory()) return result
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
                if (child.isDirectory()) {
                    if (name !in SKIP_DIRS) walk(child, depth + 1)
                    continue
                }
                scanned++
                val length = child.fileSize()
                if (length !in 1..maxBytes) continue
                try {
                    val bytes = Files.readAllBytes(child)
                    // 二进制嗅探：含 NUL 跳过（与原 Lua 实现一致）
                    if (bytes.any { it == 0.toByte() }) continue
                    val content = String(bytes, Charsets.UTF_8)
                    content.lineSequence().forEachIndexed { index, line ->
                        if (found >= maxResults) return
                        if (line.contains(pattern, ignoreCase)) {
                            found++
                            matches.set(
                                found,
                                (child.toAbsolutePath()
                                    .toString() + ":" + (index + 1) + ": " + line).toLuaValue()
                            )
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

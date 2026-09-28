package com.nekolaska.io

import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

/**
 * 同一目录里先写临时文件并 fsync，再替换目标。
 * 替换完成前，目标文件保持原来的内容。
 */
object AtomicFile {
    fun replaceText(path: String, content: String): Boolean {
        if (path.isEmpty()) return false
        return try {
            val target = Paths.get(path)
            val parent = target.parent ?: return false
            Files.createDirectories(parent)
            val temporary = Files.createTempFile(parent, ".kv-", ".tmp")
            try {
                writeSynced(temporary, content)
                moveReplacing(temporary, target)
                syncDirectory(parent)
                true
            } finally {
                Files.deleteIfExists(temporary)
            }
        } catch (_: Exception) {
            false
        }
    }

    /** 复制到目标所在目录的临时文件，fsync 后再替换。失败时目标保持原样。 */
    fun copyReplacing(source: Path, target: Path): Boolean {
        return try {
            val parent = target.parent ?: return false
            Files.createDirectories(parent)
            val temporary = Files.createTempFile(parent, ".copy-", ".tmp")
            try {
                copySynced(source, temporary)
                moveReplacing(temporary, target)
                syncDirectory(parent)
                true
            } finally {
                Files.deleteIfExists(temporary)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun writeSynced(path: Path, content: String) {
        FileChannel.open(
            path,
            StandardOpenOption.WRITE,
            StandardOpenOption.TRUNCATE_EXISTING
        ).use { channel ->
            val buffer = ByteBuffer.wrap(content.toByteArray(Charsets.UTF_8))
            while (buffer.hasRemaining()) {
                if (channel.write(buffer) < 0) {
                    throw java.io.IOException("short write")
                }
            }
            channel.force(true)
        }
    }

    private fun copySynced(source: Path, destination: Path) {
        FileChannel.open(source, StandardOpenOption.READ).use { input ->
            FileChannel.open(
                destination,
                StandardOpenOption.WRITE,
                StandardOpenOption.TRUNCATE_EXISTING
            ).use { output ->
                var position = 0L
                val size = input.size()
                while (position < size) {
                    val copied = input.transferTo(position, size - position, output)
                    if (copied <= 0) throw java.io.IOException("short copy")
                    position += copied
                }
                output.force(true)
            }
        }
    }

    private fun moveReplacing(source: Path, target: Path) {
        try {
            Files.move(
                source,
                target,
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(source, target, StandardCopyOption.REPLACE_EXISTING)
        } catch (atomicFailure: Exception) {
            try {
                Files.move(source, target, StandardCopyOption.REPLACE_EXISTING)
            } catch (replaceFailure: Exception) {
                atomicFailure.addSuppressed(replaceFailure)
                throw atomicFailure
            }
        }
    }

    private fun syncDirectory(directory: Path) {
        try {
            FileChannel.open(directory, StandardOpenOption.READ).use { channel ->
                channel.force(true)
            }
        } catch (_: Exception) {
            // 有的文件系统不允许对目录 fsync。文件内容已经 force 过。
        }
    }
}

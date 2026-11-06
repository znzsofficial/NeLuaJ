package org.luaj.android

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class FileTransactionTest {
    @Test fun missingFileAndDirectoryTypes() {
        val root = Files.createTempDirectory("file-types").toFile()
        try {
            assertEquals("dir", file.pathType(root.path))
            assertNull(file.pathType(root.resolve("missing").path))
            val child = root.resolve("child").apply { writeText("data") }
            assertEquals("file", file.pathType(child.path))
            // ENOTDIR is an error, not a missing file snapshot.
            assertTrue(runCatching { file.pathType(child.resolve("bad").path) }.isFailure)
        } finally { root.deleteRecursively() }
    }

    @Test fun binarySnapshotRestoresEveryByte() {
        val root = Files.createTempDirectory("file-binary").toFile()
        try {
            val target = root.resolve("binary")
            val bytes = ByteArray(256) { it.toByte() }
            target.writeBytes(bytes)
            val snapshot = file.readBinary(target.path)
            target.writeText("changed")
            file.saveBinary(target.path, snapshot)
            assertArrayEquals(bytes, target.readBytes())
        } finally { root.deleteRecursively() }
    }

    @Test fun renameNeverOverwritesOccupiedTarget() {
        val root = Files.createTempDirectory("file-rename").toFile()
        try {
            val source = root.resolve("source").apply { writeText("source") }
            val target = root.resolve("target").apply { writeText("target") }
            assertTrue(runCatching { file.renameExclusive(source.path, source.path) }.isFailure)
            assertTrue(runCatching { file.renameExclusive(source.path, target.path) }.isFailure)
            assertEquals("source", source.readText())
            assertEquals("target", target.readText())
            val dir = root.resolve("dir").apply { mkdir() }
            assertTrue(runCatching { file.renameExclusive(source.path, dir.path) }.isFailure)
            target.delete()
            file.renameExclusive(source.path, target.path)
            assertFalse(source.exists())
            assertEquals("source", target.readText())
        } finally { root.deleteRecursively() }
    }
}

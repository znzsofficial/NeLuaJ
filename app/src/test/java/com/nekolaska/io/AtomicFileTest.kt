package com.nekolaska.io

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import kotlin.io.path.readText

class AtomicFileTest {
    @Test
    fun failedPublicationPreservesDestinationAndReportsCause() {
        val root = Files.createTempDirectory("atomic-failure")
        val target = Files.createDirectory(root.resolve("existing"))
        val original = target.resolve("keep.txt")
        Files.writeString(original, "keep")
        val failure = runCatching {
            AtomicFile.replaceBytesOrThrow(target.toString(), byteArrayOf(1, 2))
        }.exceptionOrNull()
        assertTrue(failure != null)
        assertTrue(failure.toString().contains("existing"))
        assertEquals("keep", original.readText())
        assertEquals(1L, Files.list(root).use { it.count() })
    }

    @Test
    fun byteWriterPreservesBinaryContent() {
        val target = Files.createTempDirectory("atomic-bytes").resolve("data.bin")
        val bytes = byteArrayOf(0, -1, -128, 65)
        AtomicFile.replaceBytesOrThrow(target.toString(), bytes)
        org.junit.Assert.assertArrayEquals(bytes, Files.readAllBytes(target))
    }

    @Test
    fun replaceTextCreatesParentAndOverwritesInPlace() {
        val root = Files.createTempDirectory("atomic-file")
        val target = root.resolve("nested").resolve("note.json")
        assertTrue(AtomicFile.replaceText(target.toString(), "one"))
        assertEquals("one", target.readText())

        assertTrue(AtomicFile.replaceText(target.toString(), "二"))
        assertEquals("二", target.readText())
        assertTrue(Files.list(target.parent).use { stream ->
            stream.noneMatch { it.fileName.toString().endsWith(".tmp") }
        })
    }

    @Test
    fun replaceTextRejectsAnEmptyPath() {
        assertFalse(AtomicFile.replaceText("", "x"))
    }

    @Test
    fun copyReplacingKeepsThePreviousFileUntilTheCopyFinishes() {
        val root = Files.createTempDirectory("atomic-copy")
        val source = root.resolve("source.txt")
        val target = root.resolve("nested").resolve("target.txt")
        Files.writeString(source, "old-source")
        Files.createDirectories(target.parent)
        Files.writeString(target, "previous")

        assertTrue(AtomicFile.copyReplacing(source, target))
        assertEquals("old-source", target.readText())
        assertEquals("old-source", source.readText())
    }
}

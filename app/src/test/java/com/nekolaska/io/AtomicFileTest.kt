package com.nekolaska.io

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import kotlin.io.path.readText

class AtomicFileTest {
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

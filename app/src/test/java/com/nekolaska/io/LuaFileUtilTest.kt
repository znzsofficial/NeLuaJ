package com.nekolaska.io

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Paths
import kotlin.io.path.readText

class LuaFileUtilTest {
    @Test
    fun childRejectsSeparatorsAndDotDot() {
        val root = Files.createTempDirectory("lua-file-child").toString()
        assertEquals(
            Paths.get(root).resolve("ok").toAbsolutePath().normalize(),
            Paths.get(LuaFileUtil.child(root, "ok")!!).toAbsolutePath().normalize()
        )
        assertNull(LuaFileUtil.child(root, "../out"))
        assertNull(LuaFileUtil.child(root, "a/b"))
        assertNull(LuaFileUtil.child(root, ".."))
        assertNull(LuaFileUtil.child(root, ""))
    }

    @Test
    fun mkdirAndCreateStayInsideTheParent() {
        val root = Files.createTempDirectory("lua-file-mkdir")
        assertEquals("ok", LuaFileUtil.mkdirChild(root.toString(), "dir"))
        assertTrue(Files.isDirectory(root.resolve("dir")))
        assertEquals("bad_name", LuaFileUtil.mkdirChild(root.toString(), "../out"))
        assertFalse(Files.exists(root.parent.resolve("out")))

        assertEquals("ok", LuaFileUtil.createChild(root.toString(), "note.txt", "hi"))
        assertEquals("hi", root.resolve("note.txt").readText())
        assertEquals("exists", LuaFileUtil.createChild(root.toString(), "note.txt", "x"))
        assertEquals("bad_name", LuaFileUtil.createChild(root.toString(), "a/b.txt", "x"))
        assertFalse(Files.exists(root.resolve("a")))
    }

    @Test
    fun renameWithinDoesNotCreateParents() {
        val root = Files.createTempDirectory("lua-file-rename")
        val source = root.resolve("old.txt")
        Files.writeString(source, "body")

        assertEquals("ok", LuaFileUtil.renameWithin(source.toString(), "new.txt"))
        assertEquals("body", root.resolve("new.txt").readText())
        assertFalse(Files.exists(source))

        assertEquals("bad_name", LuaFileUtil.renameWithin(root.resolve("new.txt").toString(), "../escape"))
        assertTrue(Files.exists(root.resolve("new.txt")))
        assertFalse(Files.exists(root.parent.resolve("escape")))
    }
}

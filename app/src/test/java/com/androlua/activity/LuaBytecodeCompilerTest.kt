package com.androlua.activity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class LuaBytecodeCompilerTest {
    @Test
    fun compilesValidSourceAndReplacesOutput() {
        val directory = Files.createTempDirectory("luac-success").toFile()
        try {
            val source = directory.resolve("main.lua").apply { writeText("return 42") }
            val output = directory.resolve("main.luac").apply { writeText("old bytecode") }

            val result = LuaBytecodeCompiler.compile(source.absolutePath, output.absolutePath)

            assertTrue(result.ok)
            assertTrue(output.length() > 0)
            assertFalse(output.readText(Charsets.ISO_8859_1) == "old bytecode")
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun syntaxErrorDoesNotReplaceExistingOutput() {
        val directory = Files.createTempDirectory("luac-failure").toFile()
        try {
            val source = directory.resolve("main.lua").apply { writeText("local value = ?") }
            val output = directory.resolve("main.luac").apply { writeText("previous bytecode") }

            val result = LuaBytecodeCompiler.compile(source.absolutePath, output.absolutePath)

            assertFalse(result.ok)
            assertNotNull(result.line)
            assertFalse(result.error.contains("stack traceback", ignoreCase = true))
            assertEquals("previous bytecode", output.readText())
        } finally {
            directory.deleteRecursively()
        }
    }
}

package com.androlua

import org.luaj.Globals
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.jse.JsePlatform
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * AI agent 的 Lua 沙盒：语法检查 + 受限环境执行。
 *
 * - 每次使用全新的 standardGlobals，与主 IDE 全局环境完全隔离；
 * - print 输出重定向到内存缓冲；
 * - 剔除文件系统 / 进程 / Java 绑定（luajava）/ require 等危险入口；
 * - 独立守护线程执行 + 超时保护，防止死循环卡死主线程。
 *
 * 由 Lua 端通过 `luajava.bindClass("com.androlua.LuaSandbox")` 调用，
 * 返回 Lua 表 { ok, output, error, elapsed }。
 */
object LuaSandbox {

    /** 语法检查。无错误返回 null，有错误返回错误信息（含行号）。 */
    @JvmStatic
    fun checkSyntax(code: String): String? {
        val globals = newSandbox()
        return try {
            globals.load(code, "@agent_sandbox")
            null
        } catch (e: Throwable) {
            e.message ?: "语法错误"
        }
    }

    /** 同步运行沙盒代码（阻塞调用线程，最多 timeoutMs）。返回 Lua 表。 */
    @JvmStatic
    fun run(code: String, timeoutMs: Long): LuaTable {
        val start = System.currentTimeMillis()
        val sink = ByteArrayOutputStream()
        val out = PrintStream(sink, true, "UTF-8")
        val latch = CountDownLatch(1)
        var ok = false
        var error = ""

        val worker = Thread {
            try {
                val globals = newSandbox()
                globals.k = out // STDOUT
                globals.l = out // STDERR
                globals.load(code, "@agent_sandbox").call()
                ok = true
            } catch (e: Throwable) {
                error = e.message ?: "运行错误"
            } finally {
                latch.countDown()
            }
        }
        worker.isDaemon = true
        worker.start()

        if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            val t = LuaTable()
            t.set("ok", LuaValue.FALSE)
            t.set("output", LuaValue.valueOf(""))
            t.set("error", LuaValue.valueOf("执行超时（超过 ${timeoutMs / 1000} 秒，可能死循环）"))
            t.set("elapsed", LuaValue.valueOf(System.currentTimeMillis() - start))
            return t
        }

        out.flush()
        val output = sink.toString("UTF-8")
        val table = LuaTable()
        table.set("ok", LuaValue.valueOf(ok))
        table.set("output", LuaValue.valueOf(output))
        table.set("error", LuaValue.valueOf(error))
        table.set("elapsed", LuaValue.valueOf(System.currentTimeMillis() - start))
        return table
    }

    private fun newSandbox(): Globals {
        val g = JsePlatform.standardGlobals()
        for (k in arrayOf(
            "io", "package", "debug", "luajava", "dofile", "loadfile",
            "collectgarbage", "gcinfo", "newproxy", "module", "require"
        )) {
            g.set(k, LuaValue.NIL)
        }
        val os = g.get("os")
        if (os.istable()) {
            for (k in arrayOf(
                "execute", "exit", "remove", "rename", "tmpname", "getenv", "setlocale"
            )) {
                os.set(k, LuaValue.NIL)
            }
        }
        return g
    }
}

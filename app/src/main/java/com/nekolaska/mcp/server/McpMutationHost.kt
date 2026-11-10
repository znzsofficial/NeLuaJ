package com.nekolaska.mcp.server

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.androlua.LuaActivity
import com.nekolaska.io.FileMutationEngine
import com.nekolaska.ktx.resourceFinder
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceJavaToLua
import org.luaj.lib.jse.JsePlatform
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock

/** Trusted assets in a dedicated interpreter; UI snapshots never enter this state. */
class McpMutationHost(context: Context, projectRoot: String, agentRoot: String,
    private val isAuthorized: () -> Boolean) : AutoCloseable {
    private val closed = AtomicBoolean(false)
    private val luaLock = ReentrantLock()
    private var currentCancelled: () -> Boolean = { false }
    private val globals = JsePlatform.standardGlobals()
    private val scopePath = File(projectRoot).toPath().normalize().toString()
    private val canonicalRoot = File(scopePath).canonicalFile
    private val facade: LuaValue
    val storageDir: String

    init {
        require(File(scopePath).isAbsolute && scopePath != "/")
        val assets = context.applicationContext.assets
        globals.resourceFinder = object : org.luaj.lib.ResourceFinder {
            override fun findFile(name: String): String = name
            override fun findResource(name: String): java.io.InputStream? =
                if (name.contains("..") || name.startsWith("/")) null
                else try { assets.open(name) } catch (_: Exception) { null }
        }
        globals.get("package").set("path", "?.lua")
        val json = LuaTable().apply {
            set("encode", function { LuaValue.valueOf(toJson(it.arg1()).toString()) })
            set("decode", function { fromJson(JSONTokener(it.checkjstring(1)).nextValue()) })
        }
        globals.set("json", json)
        globals.get("package").get("loaded").set("json", json)
        globals.get("require").call(LuaValue.valueOf("mods.utils.LuaKV")).get("configure").call(LuaTable().apply {
            set("root", function { LuaValue.valueOf("$agentRoot/kv") })
            set("encode", json.get("encode")); set("decode", json.get("decode"))
        })
        val storage = globals.get("require").call(LuaValue.valueOf("mods.agent.AgentStorage"))
        storageDir = storage.get("capture").call(LuaValue.valueOf(scopePath), LuaValue.valueOf(agentRoot))
            .get("storageDir").checkjstring()
        val options = LuaTable().apply {
            set("scope", LuaTable().apply { set("scopePath", scopePath) })
            set("storageDir", storageDir)
            set("backend", CoerceJavaToLua.coerce(FileMutationEngine))
            set("notificationAuthorized", function { LuaValue.valueOf(!closed.get() && isAuthorized()) })
            set("json", json)
            set("authorized", function { LuaValue.valueOf(!closed.get() && isAuthorized() && !currentCancelled()) })
            set("resolve", function { args ->
                val relative = args.checkjstring(1)
                val resolved = File(canonicalRoot, relative).canonicalFile
                require(resolved.toPath().startsWith(canonicalRoot.toPath()) && resolved != canonicalRoot) { "path outside scope" }
                // Preserve both /sdcard spelling and symlink components for native rejection.
                LuaValue.valueOf(scopePath + "/" + relative)
            })
            set("validate", function { args ->
                if (!args.checkjstring(1).endsWith(".lua", ignoreCase = true)) LuaValue.NIL
                else try { globals.load(args.checkjstring(2), args.checkjstring(1)); LuaValue.NIL }
                catch (e: Exception) { LuaValue.valueOf(e.message ?: "invalid Lua") }
            })
            set("prepare", function { args ->
                val reply = ui("prepare", JSONObject().put("name", args.checkjstring(1))
                    .put("args", toJson(args.arg(2))).put("token", args.arg(3).optjstring("")))
                if (reply.optBoolean("error")) LuaValue.varargsOf(arrayOf(LuaValue.FALSE, LuaValue.valueOf(reply.optString("message"))))
                else reply.optString("snapshot").takeIf { it.isNotEmpty() }?.let(LuaValue::valueOf) ?: LuaValue.NIL
            })
            set("prepareRecovery", function { args ->
                val reply = ui("recovery", JSONObject().put("result", toJson(args.arg1())))
                reply.optString("snapshot").takeIf { it.isNotEmpty() }?.let(LuaValue::valueOf) ?: LuaValue.NIL
            })
            set("finish", function { args ->
                val reply = ui("finish", JSONObject().put("snapshot", args.checkjstring(1)).put("result", toJson(args.arg(4))))
                LuaValue.varargsOf(arrayOf(LuaValue.valueOf(reply.optBoolean("synced", false)), LuaValue.valueOf(reply.optString("message", "editor unavailable"))))
            })
            set("isAcknowledged", storage.get("isMutationAcknowledged"))
            set("acknowledge", storage.get("acknowledgeMutation"))
        }
        facade = globals.get("require").call(LuaValue.valueOf("mods.files.ExternalFileFacade")).get("new").call(options)
    }

    /** UI dispatch never touches luaLock; native methods return before dispatch. */
    fun execute(name: String, args: JSONObject): JSONObject = execute(name, args) { false }

    fun execute(name: String, args: JSONObject, cancelled: () -> Boolean): JSONObject {
        check(Looper.myLooper() != Looper.getMainLooper()) { "MCP mutations require a worker thread" }
        check(luaLock.tryLock()) { "MCP mutation host busy; retry after the current operation completes" }
        try {
            check(!closed.get()) { "MCP mutation host closed" }
            check(isAuthorized()) { "MCP project authorization revoked" }
            currentCancelled = cancelled
            try {
                // The facade turns recovery failure into its normal native-result envelope.
                facade.get("recover").call()
                return JSONObject(facade.get("executeJson").call(LuaValue.valueOf(name), LuaValue.valueOf(args.toString())).checkjstring())
            } finally {
                currentCancelled = { false }
            }
        } finally { luaLock.unlock() }
    }

    override fun close() { closed.set(true) }

    private fun ui(action: String, payload: JSONObject): JSONObject {
        if (closed.get() || !isAuthorized()) return JSONObject()
        payload.put("scopePath", scopePath).put("action", action)
        val cancelled = currentCancelled
        val pin = payload.optString("token").takeIf { it.isNotEmpty() }?.let(FileMutationEngine::pin)
        val task = McpUiCall(release = { pin?.close() }) {
            val activity = editor.get()
            if (closed.get() || !isAuthorized() || activity == null || activity.isFinishing || activity.isDestroyed) JSONObject()
            else {
                val reply = activity.runFunc("onMcpEditorBridge", payload.toString())
                if (reply == null) JSONObject() else JSONObject(reply.toString())
            }
        }
        val handler = Handler(Looper.getMainLooper())
        try {
            check(handler.post(task)) { "UI dispatcher stopped" }
            return task.await(5000) {
                closed.get() || !isAuthorized() || (action == "prepare" && cancelled())
            }
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw error
        } finally {
            task.abandon()
            handler.removeCallbacks(task)
        }
    }

    companion object {
        @Volatile private var editor = WeakReference<LuaActivity>(null)
        @JvmStatic fun registerEditor(activity: LuaActivity) { editor = WeakReference(activity) }
        @JvmStatic fun unregisterEditor(activity: LuaActivity) {
            if (editor.get() === activity) editor = WeakReference(null)
        }
        private fun function(block: (Varargs) -> Varargs) = object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs = block(args)
        }
        private fun fromJson(value: Any?): LuaValue = when (value) {
            null, JSONObject.NULL -> LuaValue.NIL
            is JSONObject -> LuaTable().apply { value.keys().forEach { set(it, fromJson(value.get(it))) } }
            is JSONArray -> LuaTable().apply {
                setmetatable(LuaTable().apply { set("__json_array", LuaValue.TRUE) })
                for (i in 0 until value.length()) set(i + 1, fromJson(value.get(i)))
            }
            is Boolean -> LuaValue.valueOf(value)
            is Number -> LuaValue.valueOf(value.toDouble())
            else -> LuaValue.valueOf(value.toString())
        }
        private val arrayFields = setOf("changes", "warnings", "unknownPaths", "expected", "results")
        private fun toJson(value: LuaValue, field: String? = null): Any = when {
            value.isnil() -> JSONObject.NULL
            value.isboolean() -> value.toboolean()
            value.type() == LuaValue.TNUMBER -> value.todouble()
            value.istable() -> {
                val table = value.checktable()
                val keys = table.keys()
                val array = (keys.isEmpty() && field in arrayFields) || table.getmetatable()?.get("__json_array")?.toboolean() == true ||
                    (keys.isNotEmpty() && keys.all { it.isint() && it.toint() in 1..table.length() })
                if (array) JSONArray().apply { for (i in 1..table.length()) put(toJson(table.get(i))) }
                else JSONObject().apply { keys.forEach { put(it.tojstring(), toJson(table.get(it), it.tojstring())) } }
            }
            else -> value.checkjstring()
        }
    }
}

package org.luaj.android

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import coil3.asDrawable
import coil3.executeBlocking
import coil3.imageLoader
import coil3.request.ImageRequest
import coil3.toBitmap
import com.androlua.LuaContext
import com.androlua.LuaLayout
import com.nekolaska.ktx.toLuaValue
import kotlinx.coroutines.Dispatchers
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.CoerceJavaToLua
import java.io.File
import java.util.Locale

inline fun File.ifExists(block: File.() -> Unit) {
    if (exists()) block()
}

class res(private val context: LuaContext) : TwoArgFunction() {
    override fun call(modName: LuaValue, env: LuaValue): LuaValue {
        val globals = env.checkglobals()
        val res = LuaTable().also {
            val str = string(context, globals)
            str.checktable()
            it["string"] = str
            it["drawable"] = drawable(context, globals)
            it["bitmap"] = bitmap(context, globals)
            it["layout"] = layout(context, globals)
            it["view"] = view(context, globals)
            it["font"] = font(context)
            it["language"] = str.language
        }
        if (context is Activity) {
            val configuration = context.resources.configuration
            res["dimen"] = dimen(context, globals, configuration)
            res["color"] = color(context, globals, configuration)
        }
        env["res"] = res
        if (!env["package"].isnil()) env["package"]["loaded"]["res"] = res
        return NIL
    }

    private class dimen(
        private val activity: LuaContext,
        private val globals: Globals,
        private val configuration: Configuration
    ) : LuaValue() {
        private var dimenTable: LuaTable = LuaTable()
        private var inited = false
        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        @SuppressLint("SwitchIntDef")
        override fun checktable(): LuaTable {
            var path = activity.getLuaPath("res/dimen", "init.lua")
            if (File(path).exists()) globals.loadfile(path, dimenTable).call()
            when (configuration.orientation) {
                Configuration.ORIENTATION_PORTRAIT -> {
                    path = activity.getLuaPath("res/dimen", "port.lua")
                    if (File(path).exists()) globals.loadfile(path, dimenTable).call()
                }

                Configuration.ORIENTATION_LANDSCAPE -> {
                    path = activity.getLuaPath("res/dimen", "land.lua")
                    if (File(path).exists()) globals.loadfile(path, dimenTable).call()
                }

                Configuration.ORIENTATION_UNDEFINED -> {
                    path = activity.getLuaPath("res/dimen", "undefined.lua")
                    if (File(path).exists()) globals.loadfile(path, dimenTable).call()
                }
            }
            inited = true
            return dimenTable
        }

        override fun get(key: String): LuaValue {
            if (inited) return dimenTable[key]
            return checktable()[key]
        }
    }


    private class color(
        private val activity: LuaContext,
        private val globals: Globals,
        private val configuration: Configuration
    ) : LuaValue() {
        private var colorTable = LuaTable()
        private var inited = false
        private val isDarkMode: Boolean
            get() = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun checktable(): LuaTable {
            var path = activity.getLuaPath("res/color", "init.lua")
            if (File(path).exists()) globals.loadfile(path, colorTable).call()
            path = if (isDarkMode) {
                activity.getLuaPath("res/color", "night.lua")
            } else {
                activity.getLuaPath("res/color", "day.lua")
            }
            if (File(path).exists()) globals.loadfile(path, colorTable).call()
            inited = true
            return colorTable
        }

        override fun get(key: String): LuaValue {
            if (inited) return colorTable[key]
            return checktable()[key]
        }
    }

    private class string(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private var stringTable = LuaTable()
        var language: String = Locale.getDefault().language
        private var inited = false

        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun checktable(): LuaTable {
            var p = activity.getLuaPath("res/string", "init.lua")
            if (File(p).exists()) globals.loadfile(p, stringTable).call()

            // 加载指定语言的字符串资源文件
            p = activity.getLuaPath("res/string", "$language.lua")
            if (File(p).exists()) {
                globals.loadfile(p, stringTable).call()
            } else {
                // 如果当前设备的语言不存在对应的资源文件，则加载默认的语言资源文件
                p = activity.getLuaPath("res/string", "default.lua")
                if (File(p).exists()) {
                    val defValue: LuaValue = globals.loadfile(p).call()
                    if (defValue.isstring()) {
                        language = defValue.tojstring()
                        p = activity.getLuaPath("res/string", "$language.lua")
                        if (File(p).exists()) {
                            globals.loadfile(p, stringTable).call()
                        }
                    }
                }
            }
            inited = true
            return stringTable
        }

        override fun get(key: String): LuaValue {
            if (inited) return stringTable[key]
            return checktable()[key]
        }
    }

    private class drawable(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private val loader = activity.context.imageLoader
        private val extension = listOf(
            "bmp",
            "jpeg",
            "jpg",
            "png",
            "gif",
            "svg",
            "webp",
            "heif",
            "heic",
            "avif"
        )

        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun checktable(): LuaTable {
            val t = LuaTable()
            val p = File(activity.getLuaPath("res/drawable")).list()
            if (p != null) {
                for (i in p.indices) {
                    t[i + 1] = p[i]
                }
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            val p = activity.getLuaPath("res/drawable", arg)
            extension.forEach {
                File("$p.$it").ifExists {
                    return loader.executeBlocking(
                        ImageRequest.Builder(activity.context)
                            .coroutineContext(Dispatchers.Main.immediate)
                            .data(this)
                            .build()
                    ).image?.asDrawable(activity.context.resources).toLuaValue()
                }
            }
            if (File("$p.lua").exists()) return globals.loadfile("$p.lua", globals).call()
            return NIL
        }
    }

    private class bitmap(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private val loader = activity.context.imageLoader
        private val extension = listOf(
            "bmp",
            "jpeg",
            "jpg",
            "png",
            "gif",
            "svg",
            "webp",
            "heif",
            "heic",
            "avif"
        )

        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun checktable(): LuaTable {
            val t = LuaTable()
            val p = File(activity.getLuaPath("res/drawable")).list()
            if (p != null) {
                for (i in p.indices) {
                    t[i + 1] = p[i]
                }
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            try {
                val p = activity.getLuaPath("res/drawable", arg)
                extension.forEach {
                    File("$p.$it").ifExists {
                        return loader.executeBlocking(
                            ImageRequest.Builder(activity.context)
                                .coroutineContext(Dispatchers.Main.immediate)
                                .data(this)
                                .build()
                        ).image?.toBitmap().toLuaValue()
                    }
                }
                if (File("$p.lua").exists()) return globals.loadfile("$p.lua", globals).call()
                return NIL
            } catch (e: Exception) {
                throw LuaError(e)
            }
        }
    }

    private class layout(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun checktable(): LuaTable {
            val t = LuaTable()
            val p = File(activity.getLuaPath("res/layout")).list()
            if (p != null) {
                for (i in p.indices) {
                    t[i + 1] = p[i]
                }
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            val p = activity.getLuaPath("res/layout", "$arg.lua")
            return globals.loadfile(p, globals).call()
        }
    }

    private class view(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun checktable(): LuaTable {
            val t = LuaTable()
            val p = File(activity.getLuaPath("res/layout")).list()
            if (p != null) {
                for (i in p.indices) {
                    t[i + 1] = p[i]
                }
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            val p = activity.getLuaPath("res/layout", "$arg.lua")
            return LuaLayout(activity as Context)
                .load(globals.loadfile(p, globals).call(), globals)
        }
    }

    private class font(private val activity: LuaContext) : LuaValue() {
        override fun type(): Int {
            return TTABLE
        }

        override fun typename(): String {
            return "table"
        }

        override fun checktable(): LuaTable {
            val t = LuaTable()
            val p = File(activity.getLuaPath("res/font")).list()
            if (p != null) {
                for (i in p.indices) {
                    t[i + 1] = p[i]
                }
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            try {
                val p = activity.getLuaPath("res/font", arg)
                if (File("$p.ttf").exists()) return CoerceJavaToLua.coerce(
                    Typeface.createFromFile(
                        File(
                            "$p.ttf"
                        )
                    )
                )
                if (File("$p.otf").exists()) return CoerceJavaToLua.coerce(
                    Typeface.createFromFile(
                        File(
                            "$p.otf"
                        )
                    )
                )
                return NIL
            } catch (e: Exception) {
                throw LuaError(e)
            }
        }
    }
}

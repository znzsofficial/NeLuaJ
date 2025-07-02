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
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.toLuaValue
import kotlinx.coroutines.Dispatchers
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
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
            it["raw"] = raw(context)
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
        private val configuration: Configuration,
    ) : LuaValue() {
        private var dimenTable: LuaTable = LuaTable()
        private var loaded = false
        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

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
            loaded = true
            return dimenTable
        }

        override fun get(key: String): LuaValue {
            if (loaded) return dimenTable[key]
            return checktable()[key]
        }
    }

    private class color(
        private val activity: LuaContext,
        private val globals: Globals,
        private val configuration: Configuration
    ) : LuaValue() {
        private var colorTable = LuaTable()
        private var loaded = false
        private val isDarkMode: Boolean
            get() = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

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
            loaded = true
            return colorTable
        }

        override fun get(key: String): LuaValue {
            if (loaded) return colorTable[key]
            return checktable()[key]
        }
    }

    private class string(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private var stringTable = LuaTable()

        // 'language' 将会反映实际加载的资源文件名（不含.lua后缀）
        var language: String = ""
            private set

        private var loaded = false

        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun checktable(): LuaTable {
            // 1. 首先加载通用的 init.lua，它包含所有语言共享的字符串
            val path = activity.getLuaPath("res/string", "init.lua")
            File(path).ifExists {
                globals.loadfile(this.path, stringTable).call()
            }

            // 2. 实现多级回退的语言加载逻辑
            loadLocalizedStrings()

            loaded = true
            return stringTable
        }

        private fun loadLocalizedStrings() {
            val currentLocale = Locale.getDefault()
            val lang = currentLocale.language // 例如 "zh"
            val country = currentLocale.country // 例如 "CN"

            // 尝试加载最具体的语言资源（例如 "zh-rCN.lua"）
            if (country.isNotEmpty()) {
                val specificLangTag = "$lang-r$country"
                if (tryLoadLangFile(specificLangTag)) {
                    language = specificLangTag
                    return // 加载成功，直接返回
                }
            }

            // 如果最具体的资源不存在，则回退到仅语言的资源（例如 "zh.lua"）
            if (tryLoadLangFile(lang)) {
                language = lang
                return // 加载成功，直接返回
            }

            // 如果上述资源都不存在，则使用 default.lua 指定的默认语言
            val defaultPath = activity.getLuaPath("res/string", "default.lua")
            File(defaultPath).ifExists {
                val defValue: LuaValue = globals.loadfile(this.path).call()
                if (defValue.isstring()) {
                    val defaultLanguage = defValue.tojstring()
                    language = defaultLanguage
                    // 加载 default.lua 中指定的语言文件
                    tryLoadLangFile(defaultLanguage)
                }
            }
        }

        /**
         * 尝试加载指定语言的资源文件
         * @param langTag 语言标签 (例如 "zh-rCN" 或 "zh")
         * @return 如果文件存在并加载成功，返回 true，否则返回 false
         */
        private fun tryLoadLangFile(langTag: String): Boolean {
            val path = activity.getLuaPath("res/string", "$langTag.lua")
            val file = File(path)
            if (file.exists()) {
                globals.loadfile(path, stringTable).call()
                return true
            }
            return false
        }

        override fun get(key: String): LuaValue {
            if (loaded) return stringTable[key]
            return checktable()[key]
        }
    }

    companion object {
        val imageExtensions = listOf(
            "png",
            "jpg",
            "gif",
            "webp",
            "jpeg",
            "svg",
            "bmp",
            "heif",
            "heic",
            "avif"
        )

        private fun loadImageValue(
            activity: LuaContext,
            globals: Globals,
            arg: String,
            isBitmap: Boolean
        ): LuaValue {
            val p = activity.getLuaPath("res/drawable", arg)
            // 查找图片文件
            imageExtensions.forEach {
                File("$p.$it").ifExists {
                    val imageResult = activity.context.imageLoader.executeBlocking(
                        ImageRequest.Builder(activity.context)
                            .coroutineContext(Dispatchers.Main.immediate)
                            .data(this)
                            .build()
                    )
                    val image = imageResult.image
                    return if (isBitmap) {
                        image?.toBitmap().toLuaValue()
                    } else {
                        image?.asDrawable(activity.context.resources).toLuaValue()
                    }
                }
            }
            // 查找 Lua 文件
            if (File("$p.lua").exists()) return globals.loadfile("$p.lua", globals).call()
            return NIL
        }
    }

    private class drawable(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private val cache = LuaTable()
        override fun type() = TTABLE
        override fun typename() = "table"
        override fun get(key: LuaValue) = get(key.tojstring())
        override fun get(arg: String): LuaValue {
            val cached = cache.get(arg)
            if (!cached.isnil()) return cached
            val result = loadImageValue(activity, globals, arg, isBitmap = false)
            cache.set(arg, result)
            return result
        }
    }

    private class bitmap(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        private val cache = LuaTable()
        override fun type() = TTABLE
        override fun typename() = "table"
        override fun get(key: LuaValue) = get(key.tojstring())
        override fun get(arg: String): LuaValue {
            val cached = cache.get(arg)
            if (!cached.isnil()) return cached
            val result = loadImageValue(activity, globals, arg, isBitmap = true)
            cache.set(arg, result)
            return result
        }
    }

    private class layout(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun checktable(): LuaTable {
            val t = LuaTable()
            File(activity.getLuaPath("res/layout")).list()?.forEachIndexed { index, fileName ->
                t[index + 1] = fileName
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
        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun checktable(): LuaTable {
            val t = LuaTable()
            File(activity.getLuaPath("res/layout")).list()?.forEachIndexed { index, fileName ->
                t[index + 1] = fileName
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
        private val cache = LuaTable()

        override fun type() = TTABLE
        override fun typename() = "table"

        override fun checktable(): LuaTable {
            val t = LuaTable()
            File(activity.getLuaPath("res/font")).list()?.forEachIndexed { index, fileName ->
                t[index + 1] = fileName
            }
            return t
        }

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            // 1. 优先从缓存中获取
            val cached = cache.get(arg)
            if (!cached.isnil()) {
                return cached
            }

            // 2. 缓存未命中，执行加载逻辑
            val result: LuaValue = try {
                val p = activity.getLuaPath("res/font", arg)
                var typeface: Typeface? = null

                // 尝试 .ttf
                val ttfFile = File("$p.ttf")
                if (ttfFile.exists()) {
                    typeface = Typeface.createFromFile(ttfFile)
                }

                // 如果 ttf 不存在，尝试 .otf
                if (typeface == null) {
                    val otfFile = File("$p.otf")
                    if (otfFile.exists()) {
                        typeface = Typeface.createFromFile(otfFile)
                    }
                }

                if (typeface != null) {
                    CoerceJavaToLua.coerce(typeface)
                } else {
                    NIL
                }
            } catch (e: Exception) {
                throw LuaError("Failed to load font '$arg': ${e.message}")
            }

            // 3. 将结果（无论是成功加载的Typeface还是NIL）存入缓存
            cache.set(arg, result)
            return result
        }
    }

    private class raw(private val context: LuaContext) : LuaValue() {
        private val cache = LuaTable()
        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun get(arg: String): LuaValue {
            // 1. 优先从缓存中获取
            val cached = cache.get(arg)
            if (!cached.isnil()) {
                return cached
            }

            // 2. 缓存未命中，执行查找逻辑
            val rawDir = File(context.getLuaPath("res/raw"))

            // listFiles() 可能会返回 null
            val files = rawDir.listFiles()
            if (files != null) {
                for (file in files) {
                    // 检查文件名（不含扩展名）是否匹配
                    if (file.isFile && file.nameWithoutExtension == arg) {
                        val result = CoerceJavaToLua.coerce(file)
                        // 存入缓存并返回
                        cache.set(arg, result)
                        return result
                    }
                }
            }

            // 3. 如果找不到，缓存NIL防止下次重复查找
            cache.set(arg, NIL)
            return NIL
        }

        override fun checktable(): LuaTable? {
            val t = LuaTable()
            File(context.getLuaPath("res/raw")).list()?.forEachIndexed { index, fileName ->
                t[index + 1] = fileName
            }
            return t
        }

        override fun invoke(args: Varargs): Varargs {
            val key = args.firstArg()
            val encoding = args.optjstring(2, "UTF-8")
            val luaFile = get(key) // 使用我们增强的 get 方法
            if (luaFile.isnil()) {
                return NIL
            }
            val file = luaFile.touserdata(File::class.java)
            return valueOf(file.readText(charset(encoding)))
        }
    }
}

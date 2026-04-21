package org.luaj.android

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import androidx.core.graphics.BlendModeColorFilterCompat
import androidx.core.graphics.BlendModeCompat
import coil3.asDrawable
import coil3.executeBlocking
import coil3.imageLoader
import coil3.request.ImageRequest
import coil3.toBitmap
import com.androlua.LuaContext
import com.androlua.LuaLayout
import com.nekolaska.ktx.ifNotNil
import com.nekolaska.ktx.toLuaValue
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.OneArgFunction
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.CoerceJavaToLua
import java.io.File
import java.util.Locale

inline fun File.ifExists(block: File.() -> Unit) {
    if (exists()) block()
}

class res(private val context: LuaContext) : TwoArgFunction() {

    private var cachedLanguage: String? = null

    private fun getLanguagePath(globals: Globals): String {
        cachedLanguage?.let { return it }

        val currentLocale = Locale.getDefault()
        val lang = currentLocale.language
        val country = currentLocale.country

        // 1. 尝试的具体标签 (zh-rCN)
        if (country.isNotEmpty()) {
            val specificTag = "$lang-r$country"
            if (File(context.getLuaPath("res/string", "$specificTag.lua")).exists()) {
                return specificTag.also { cachedLanguage = it }
            }
        }

        // 2. 尝试纯语言标签 (zh)
        if (File(context.getLuaPath("res/string", "$lang.lua")).exists()) {
            return lang.also { cachedLanguage = it }
        }

        // 3. 读取 default.lua
        val defaultPath = context.getLuaPath("res/string", "default.lua")
        if (File(defaultPath).exists()) {
            val defValue = globals.loadfile(defaultPath).call()
            if (defValue.isstring()) {
                return defValue.tojstring().also { cachedLanguage = it }
            }
        }

        return "en".also { cachedLanguage = it } // 终极兜底
    }

    override fun call(modName: LuaValue, env: LuaValue): LuaValue {
        val globals = env.checkglobals()
        val language = getLanguagePath(globals)

        val resTable = LuaTable().also {
            val str = string(context, globals, language)
            it["string"] = str
            it["drawable"] = drawable(context, globals)
            it["bitmap"] = bitmap(context, globals)
            it["layout"] = layout(context, globals)
            it["view"] = view(context, globals)
            it["font"] = font(context)
            it["raw"] = raw(context)
            it["language"] = valueOf(language)
            it["plurals"] = plurals(context, globals, language)
        }
        if (context is Activity) {
            val configuration = context.resources.configuration
            resTable["dimen"] = dimen(context, globals, configuration)
            resTable["color"] = color(context, globals, configuration)
        }
        env["res"] = resTable
        if (!env["package"].isnil()) env["package"]["loaded"]["res"] = resTable
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

    private class string(
        private val activity: LuaContext,
        private val globals: Globals,
        val language: String
    ) : LuaValue() {
        private var stringTable = LuaTable()
        private var loaded = false

        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun get(key: LuaValue): LuaValue {
            return get(key.tojstring())
        }

        override fun checktable(): LuaTable {
            if (loaded) return stringTable

            // 1. 加载通用的 init.lua
            val initPath = activity.getLuaPath("res/string", "init.lua")
            File(initPath).ifExists {
                globals.loadfile(this.path, stringTable).call()
            }

            // 2. 使用计算好的 language 标签加载对应的语言文件
            val langPath = activity.getLuaPath("res/string", "$language.lua")
            File(langPath).ifExists {
                globals.loadfile(this.path, stringTable).call()
            }

            loaded = true
            return stringTable
        }

        override fun get(key: String): LuaValue {
            if (loaded) return stringTable[key]
            return checktable()[key]
        }
    }

    private class plurals(
        private val activity: LuaContext,
        private val globals: Globals,
        private val language: String
    ) : LuaValue() { // 修改为继承 LuaValue 以支持属性访问
        private var pluralsTable = LuaTable()
        private var loaded = false

        override fun type(): Int = TTABLE
        override fun typename(): String = "table"

        override fun get(key: LuaValue): LuaValue {
            val keyStr = key.tojstring()
            if (!loaded) checktable()
            
            val item = pluralsTable[keyStr]
            if (item.istable()) {
                return object : OneArgFunction() {
                    override fun call(quantity: LuaValue): LuaValue {
                        val pluralTable = item.checktable()
                        val q = quantity.toint()
                        val rawTemplate = when (q) {
                            0 -> pluralTable["zero"].ifNil { pluralTable["other"] }
                            1 -> pluralTable["one"].ifNil { pluralTable["other"] }
                            2 -> pluralTable["two"].ifNil { pluralTable["other"] }
                            else -> pluralTable["other"]
                        }
                        
                        // 处理 %d 替换逻辑
                        if (rawTemplate.isstring()) {
                            val templateStr = rawTemplate.tojstring()
                            if (templateStr.contains("%d")) {
                                return valueOf(templateStr.replace("%d", q.toString()))
                            }
                            return rawTemplate
                        }
                        return rawTemplate
                    }
                }
            }
            return NIL
        }

        private fun LuaValue.ifNil(block: () -> LuaValue): LuaValue {
            return if (this.isnil()) block() else this
        }

        override fun checktable(): LuaTable {
            if (loaded) return pluralsTable

            // 1. 加载通用的 init.lua
            val path = activity.getLuaPath("res/plurals", "init.lua")
            File(path).ifExists {
                globals.loadfile(path, pluralsTable).call()
            }

            // 2. 使用计算好的 language 标签加载对应的语言文件
            val langPath = activity.getLuaPath("res/plurals", "$language.lua")
            File(langPath).ifExists {
                globals.loadfile(this.path, pluralsTable).call()
            }

            loaded = true
            return pluralsTable
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
                            .data(this)
                            .build()
                    )
                    val image = imageResult.image
                    return if (isBitmap) {
                        image?.toBitmap().toLuaValue()
                    } else {
                        image?.asDrawable(activity.context.resources).toLuaValue()
                        //(drawable as? Animatable)?.start()
                    }
                }
            }
            // 查找 Lua 文件
            if (File("$p.lua").exists()) return globals.loadfile("$p.lua", globals).call()
            return NIL
        }
    }

    private class drawable(private val activity: LuaContext, private val globals: Globals) :
        TwoArgFunction() {
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

        override fun call(arg1: LuaValue, arg2: LuaValue): LuaValue {
            if (arg1.isnil()) return NIL
            val drawable = get(arg1)
            if (drawable.isnil()) return NIL
            arg2.ifNotNil()?.let {
                if (it.isfunction()) {
                    it.call(drawable)
                } else if (it.isint()) {
                    drawable["setColorFilter"].jcall(
                        BlendModeColorFilterCompat.createBlendModeColorFilterCompat(
                            it.toint(),
                            BlendModeCompat.SRC_ATOP
                        )
                    )
                }
            }
            return drawable
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

    private class raw(private val context: LuaContext) : TwoArgFunction() {
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

        override fun call(key: LuaValue, charset: LuaValue): LuaValue {
            val encoding = if (charset.isnil()) "UTF-8"
            else charset.tojstring()
            val luaFile = get(key) // 使用我们增强的 get 方法
            if (luaFile.isnil()) {
                return NIL
            }
            val file = luaFile.touserdata(File::class.java)
            return valueOf(file.readText(charset(encoding)))
        }

    }
}

package org.luaj.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import com.androlua.LuaActivity
import com.androlua.LuaBitmap
import com.androlua.LuaBitmapDrawable
import com.androlua.LuaContext
import com.androlua.LuaLayout
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.jse.CoerceJavaToLua
import java.io.File
import java.util.Locale

class res(private val context: LuaContext) : TwoArgFunction() {
    override fun call(modName: LuaValue, env: LuaValue): LuaValue {
        val globals = env.checkglobals()
        val res = LuaTable()
        res["string"] = string(context, globals)
        res["drawable"] = drawable(context, globals)
        res["bitmap"] = bitmap(context, globals)
        res["layout"] = layout(context, globals)
        res["view"] = view(context, globals)
        res["font"] = font(context)
        if (context is LuaActivity) {
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
            val mLanguage = Locale.getDefault().language
            var p = activity.getLuaPath("res/string", "init.lua")
            if (File(p).exists()) globals.loadfile(p, stringTable).call()

            // 加载指定语言的字符串资源文件
            p = activity.getLuaPath("res/string", "$mLanguage.lua")
            if (File(p).exists()) {
                globals.loadfile(p, stringTable).call()
            } else {
                // 如果当前设备的语言不存在对应的资源文件，则加载默认的语言资源文件
                p = activity.getLuaPath("res/string", "default.lua")
                if (File(p).exists()) {
                    val defValue: LuaValue = globals.loadfile(p).call()
                    if (defValue.isstring()) {
                        val defLanguage = defValue.tojstring()
                        p = activity.getLuaPath("res/string", "$defLanguage.lua")
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
            if (File("$p.png").exists()) return CoerceJavaToLua.coerce(
                LuaBitmapDrawable(
                    activity,
                    "$p.png"
                )
            )
            if (File("$p.jpg").exists()) return CoerceJavaToLua.coerce(
                LuaBitmapDrawable(
                    activity,
                    "$p.jpg"
                )
            )
            if (File("$p.gif").exists()) return CoerceJavaToLua.coerce(
                LuaBitmapDrawable(
                    activity,
                    "$p.gif"
                )
            )
            if (File("$p.lua").exists()) return globals.loadfile("$p.lua", globals).call()
            return NIL
        }
    }

    private class bitmap(private val activity: LuaContext, private val globals: Globals) :
        LuaValue() {
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
                if (File("$p.png").exists()) return CoerceJavaToLua.coerce(
                    LuaBitmap.getBitmap(
                        activity,
                        "$p.png"
                    )
                )
                if (File("$p.jpg").exists()) return CoerceJavaToLua.coerce(
                    LuaBitmap.getBitmap(
                        activity,
                        "$p.jpg"
                    )
                )
                if (File("$p.gif").exists()) return CoerceJavaToLua.coerce(
                    LuaBitmap.getBitmap(
                        activity,
                        "$p.gif"
                    )
                )
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

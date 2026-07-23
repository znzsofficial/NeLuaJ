package com.androlua.layout

import android.content.Context
import android.content.res.ColorStateList
import android.util.DisplayMetrics
import android.util.TypedValue
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import com.androlua.LuaContext
import com.google.android.material.color.MaterialColors
import com.nekolaska.ktx.asString
import org.luaj.LuaError
import org.luaj.LuaValue
import java.util.Locale

/**
 * 布局表字符串 / LuaValue → Java 类型（尺寸、枚举、颜色、布尔）。
 */
internal class LayoutValueParser(
    private val context: Context,
    private val luaContext: LuaContext,
    private val dm: DisplayMetrics,
) {
    private val themeAttrValueCache = HashMap<String, Any>()
    private val noValue = Any()

    fun toValue(str: String, attr: String? = null): Any? {
        if (str == "nil") return 0

        val enumMap = attr?.let { LayoutEnums.enumMapForAttr(it) }

        if (str.indexOf('|') >= 0) {
            var ret = 0
            var unknown: ArrayList<String>? = null
            val fallback = if (enumMap == null) LayoutEnums.gravity else null
            // 手动切分，避免 split 产生中间 List（gravity 热路径）
            var start = 0
            val n = str.length
            var i = 0
            while (i <= n) {
                if (i == n || str[i] == '|') {
                    var a = start
                    var b = i
                    while (a < b && str[a] <= ' ') a++
                    while (b > a && str[b - 1] <= ' ') b--
                    if (a < b) {
                        val s = str.substring(a, b)
                        val v = enumMap?.get(s) ?: LayoutEnums.sizeTokens[s] ?: fallback?.get(s)
                        if (v != null) {
                            ret = ret or v
                        } else {
                            (unknown ?: ArrayList<String>(2).also { unknown = it }).add(s)
                        }
                    }
                    start = i + 1
                }
                i++
            }
            if (unknown != null) {
                val where = attr?.let { " ($it)" } ?: ""
                luaContext.sendMsg(
                    "loadlayout: 未知枚举 flag$where: ${unknown.joinToString()}（整串: $str）"
                )
            }
            return ret
        }

        enumMap?.get(str)?.let { return it }
        LayoutEnums.sizeTokens[str]?.let { return it }
        if (enumMap != null && str.toLongOrNull() == null && str.toDoubleOrNull() == null &&
            !str.startsWith("#") && !str.startsWith("?") && !str.endsWith("dp") &&
            !str.endsWith("sp") && !str.endsWith("px") && !str.contains('%')
        ) {
            luaContext.sendMsg("loadlayout: 属性 $attr 未识别枚举值 \"$str\"")
        }

        if (str.startsWith("#")) {
            return runCatching { parseColor(str) }.getOrElse {
                throw LuaError("无法解析颜色: $str")
            }
        }

        val len = str.length
        if (str.endsWith("%")) {
            return str.dropLast(1).toFloatOrNull()?.times(luaContext.width)?.div(100)
        }
        if (len >= 3 && str[len - 2] == '%') {
            val f = str.dropLast(2).toFloatOrNull() ?: return str
            return when (str.last()) {
                'w' -> f * luaContext.width / 100
                'h' -> f * luaContext.height / 100
                else -> str
            }
        }
        if (len >= 3) {
            val unit = str.takeLast(2)
            LayoutEnums.dimensionUnits[unit]?.let { type ->
                str.dropLast(2).toFloatOrNull()?.let { value ->
                    return TypedValue.applyDimension(type, value, dm)
                }
            }
        }

        resolveThemeAttributeValue(str.trim())?.let { return it }
        str.toLongOrNull()?.let { return it }
        str.toDoubleOrNull()?.let { return it }
        return str
    }

    fun toBoolean(value: LuaValue): Boolean {
        if (value.isboolean()) return value.toboolean()
        if (value.isnumber()) return value.toint() != 0
        if (value.isstring()) {
            return when (value.asString().lowercase(Locale.ROOT)) {
                "true", "1", "yes", "on" -> true
                "false", "0", "no", "off" -> false
                else -> value.toboolean()
            }
        }
        return value.toboolean()
    }

    fun toDimensionPx(value: LuaValue, attr: String? = null): Float {
        return when {
            value.isnumber() -> value.todouble().toFloat()
            value.isstring() -> {
                val v = toValue(value.asString(), attr)
                when (v) {
                    is Number -> v.toFloat()
                    else -> throw LuaError("无法解析尺寸: ${value.asString()}")
                }
            }
            else -> throw LuaError("尺寸需要 number 或 \"12dp\" 字符串，实际为 ${value.typename()}")
        }
    }

    fun toIntValue(value: LuaValue, attr: String? = null): Int {
        return when {
            value.isnumber() -> value.toint()
            value.isstring() -> {
                val v = toValue(value.asString(), attr)
                when (v) {
                    is Number -> v.toInt()
                    else -> throw LuaError("无法解析整数/枚举: ${value.asString()}")
                }
            }
            else -> value.toint()
        }
    }

    fun toLayoutSize(value: LuaValue): Int {
        return when {
            value.isnumber() -> value.toint()
            value.isstring() -> {
                val v = toValue(value.asString())
                when (v) {
                    is Number -> v.toInt()
                    else -> throw LuaError("无法解析 layout 尺寸: ${value.asString()}")
                }
            }
            else -> value.toint()
        }
    }

    fun parseColor(colorString: String): Int {
        val s = colorString.trim()
        if (s.isEmpty()) throw LuaError("颜色字符串为空")
        if (s[0] == '#') {
            return runCatching { s.toColorInt() }.getOrElse {
                val hex = s.substring(1)
                when (hex.length) {
                    3 -> {
                        // #RGB → #FFRRGGBB
                        val r = hex[0].toString().repeat(2)
                        val g = hex[1].toString().repeat(2)
                        val b = hex[2].toString().repeat(2)
                        ("FF$r$g$b").toLong(16).toInt()
                    }
                    4 -> {
                        // #ARGB
                        val a = hex[0].toString().repeat(2)
                        val r = hex[1].toString().repeat(2)
                        val g = hex[2].toString().repeat(2)
                        val b = hex[3].toString().repeat(2)
                        ("$a$r$g$b").toLong(16).toInt()
                    }
                    6 -> (hex.toLong(16) or 0xFF000000L).toInt()
                    8 -> hex.toLong(16).toInt()
                    else -> throw LuaError("无法解析颜色: $s")
                }
            }
        }
        s.toLongOrNull()?.let { return it.toInt() }
        throw LuaError("无法解析颜色: $s")
    }

    fun toColorIntValue(value: LuaValue): Int {
        when {
            value.isnumber() -> return value.toint()
            value.isstring() -> {
                val str = value.asString().trim()
                if (str.startsWith("?")) {
                    return asColorInt(resolveThemeAttributeValue(str), str)
                        ?: materialColorOrNull(str)
                        ?: throw LuaError("无法将主题属性解析为颜色: $str")
                }
                return parseColor(str)
            }
            value.isuserdata(ColorStateList::class.java) -> {
                val csl = value.touserdata(ColorStateList::class.java) as ColorStateList
                return csl.defaultColor
            }
            else -> throw LuaError(
                "颜色需要 int / \"#RRGGBB\" / \"?attr/…\" / ColorStateList，实际为 ${value.typename()}"
            )
        }
    }

    /**
     * 统一成 ColorStateList，供 iconTint / backgroundTint 等使用。
     * 兼容：ColorStateList userdata、int、long（Lua 数字）、"#AARRGGBB"、"?attr/…"。
     */
    fun toColorStateList(value: LuaValue): ColorStateList {
        if (value.isnil()) throw LuaError("颜色不能为 nil")
        if (value.isuserdata()) {
            when (val raw = value.touserdata()) {
                is ColorStateList -> return raw
                is Number -> return ColorStateList.valueOf(raw.toInt())
            }
            if (value.isuserdata(ColorStateList::class.java)) {
                return value.touserdata(ColorStateList::class.java) as ColorStateList
            }
        }
        if (value.isstring()) {
            val str = value.asString().trim()
            if (str.startsWith("?")) {
                asColorStateList(resolveThemeAttributeValue(str))?.let { return it }
                materialColorOrNull(str)?.let { return ColorStateList.valueOf(it) }
            }
        }
        return try {
            ColorStateList.valueOf(toColorIntValue(value))
        } catch (e: LuaError) {
            throw e
        } catch (e: Exception) {
            throw LuaError("无法转为 ColorStateList: ${value.typename()} — ${e.message}")
        }
    }

    fun resolveThemeAttributeValue(ref: String): Any? {
        if (!ref.startsWith("?")) return null
        val cached = themeAttrValueCache[ref]
        if (cached === noValue) return null
        if (cached != null) return cached

        val attrId = lookupThemeAttrId(ref)
        if (attrId == 0) {
            themeAttrValueCache[ref] = noValue
            return null
        }

        val tv = TypedValue()
        if (!context.theme.resolveAttribute(attrId, tv, true)) {
            themeAttrValueCache[ref] = noValue
            return null
        }

        // 资源引用优先展开（鸿蒙动态色常停在 color-v31 / ColorStateList）
        val fromRes = if (tv.resourceId != 0) {
            colorIntFromResId(tv.resourceId) ?: colorStateListFromResId(tv.resourceId)
        } else null

        val resolved: Any? = fromRes ?: when (tv.type) {
            TypedValue.TYPE_DIMENSION -> tv.getDimension(dm)
            TypedValue.TYPE_FLOAT -> tv.float
            in TypedValue.TYPE_FIRST_INT..TypedValue.TYPE_LAST_INT -> tv.data
            TypedValue.TYPE_STRING -> {
                val s = tv.string?.toString()
                when {
                    s.isNullOrBlank() -> null
                    s.startsWith("#") -> runCatching { parseColor(s) }.getOrNull()
                    else -> toValue(s)
                }
            }
            else -> tv.resourceId.takeIf { it != 0 } ?: tv.data
        }
        themeAttrValueCache[ref] = resolved ?: noValue
        return resolved
    }

    private fun lookupThemeAttrId(ref: String): Int {
        val androidOnly = ref.startsWith("?android:attr/")
        val name = when {
            androidOnly -> ref.removePrefix("?android:attr/")
            ref.startsWith("?attr/") -> ref.removePrefix("?attr/")
            ref.startsWith("?") -> ref.removePrefix("?")
            else -> return 0
        }
        if (name.isBlank()) return 0
        if (androidOnly) {
            return context.resources.getIdentifier(name, "attr", "android")
        }
        return context.resources.getIdentifier(name, "attr", context.packageName)
            .takeIf { it != 0 }
            ?: context.resources.getIdentifier(name, "attr", "android")
    }

    /** resolve 结果 → 颜色 int；非颜色类型返回 null */
    private fun asColorInt(resolved: Any?, ref: String? = null): Int? = when (resolved) {
        is Number -> resolved.toInt()
        is ColorStateList -> resolved.defaultColor
        else -> null
    }

    private fun asColorStateList(resolved: Any?): ColorStateList? = when (resolved) {
        is ColorStateList -> resolved
        is Number -> ColorStateList.valueOf(resolved.toInt())
        else -> null
    }

    /** resolve 失败时再试 MaterialColors（不抢缓存主路径） */
    private fun materialColorOrNull(ref: String): Int? {
        val attrId = lookupThemeAttrId(ref)
        if (attrId == 0) return null
        return runCatching {
            MaterialColors.getColor(context, attrId, "LayoutValueParser")
        }.getOrNull()
    }

    private fun colorIntFromResId(resId: Int): Int? {
        if (resId == 0) return null
        return runCatching { ContextCompat.getColor(context, resId) }.getOrNull()
            ?: colorStateListFromResId(resId)?.defaultColor
    }

    private fun colorStateListFromResId(resId: Int): ColorStateList? {
        if (resId == 0) return null
        return runCatching { ContextCompat.getColorStateList(context, resId) }.getOrNull()
    }
}

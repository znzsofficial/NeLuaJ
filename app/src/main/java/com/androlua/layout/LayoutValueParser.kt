package com.androlua.layout

import android.content.Context
import android.content.res.ColorStateList
import android.util.DisplayMetrics
import android.util.TypedValue
import androidx.core.graphics.toColorInt
import com.androlua.LuaContext
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
                    "loadlayout: 未知枚举 flag$where: ${unknown!!.joinToString()}（整串: $str）"
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
                    val resolved = resolveThemeAttributeValue(str)
                    if (resolved is Number) return resolved.toInt()
                    throw LuaError("无法将主题属性解析为颜色: $str")
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

    fun toColorStateList(value: LuaValue): ColorStateList {
        if (value.isuserdata(ColorStateList::class.java)) {
            return value.touserdata(ColorStateList::class.java) as ColorStateList
        }
        return ColorStateList.valueOf(toColorIntValue(value))
    }

    fun resolveThemeAttributeValue(ref: String): Any? {
        if (!ref.startsWith("?")) return null
        val cached = themeAttrValueCache[ref]
        if (cached === noValue) return null
        if (cached != null) return cached

        val attrName = when {
            ref.startsWith("?attr/") -> ref.removePrefix("?attr/")
            ref.startsWith("?android:attr/") -> ref.removePrefix("?android:attr/")
            else -> ref.removePrefix("?")
        }
        if (attrName.isBlank()) {
            themeAttrValueCache[ref] = noValue
            return null
        }

        val attrId = when {
            ref.startsWith("?android:attr/") ->
                context.resources.getIdentifier(attrName, "attr", "android")
            else -> context.resources.getIdentifier(attrName, "attr", context.packageName)
                .takeIf { it != 0 }
                ?: context.resources.getIdentifier(attrName, "attr", "android")
        }
        if (attrId == 0) {
            themeAttrValueCache[ref] = noValue
            return null
        }

        val outValue = TypedValue()
        if (!context.theme.resolveAttribute(attrId, outValue, true)) {
            themeAttrValueCache[ref] = noValue
            return null
        }

        val resolved: Any? = when (outValue.type) {
            TypedValue.TYPE_DIMENSION -> outValue.getDimension(dm)
            TypedValue.TYPE_FLOAT -> outValue.float
            in TypedValue.TYPE_FIRST_INT..TypedValue.TYPE_LAST_INT -> outValue.data
            TypedValue.TYPE_STRING -> outValue.string?.toString()?.let { toValue(it) }
            else -> outValue.resourceId.takeIf { it != 0 } ?: outValue.data
        }
        themeAttrValueCache[ref] = resolved ?: noValue
        return resolved
    }
}

package com.androlua.layout

import android.content.Context
import android.util.AttributeSet
import androidx.appcompat.view.ContextThemeWrapper
import com.androlua.LuaContext
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import org.luaj.LuaError
import org.luaj.LuaValue
import org.luaj.LuaValue.NIL
import java.lang.reflect.Constructor

/**
 * 根据 theme / style / styleAttr / styleRes 构造 View。
 *
 * 策略（成功即返回）：
 * 1. styleRes + 四参构造 → (ctx, attrs, styleAttr, styleRes)
 * 2. styleRes → 三参第三参 = styleRes（MaterialTextField 等无四参类）
 * 3. styleAttr → 三参第三参 = styleAttr
 * 4. 单参 (ctx)（可先 theme → ContextThemeWrapper）
 *
 * 注意：attrs 恒为 null（无 XML AttributeSet）；style 靠构造参 + 后续 setter。
 */
internal class LayoutViewFactory(
    private val initialContext: Context,
    private val luaContext: LuaContext,
    private val luaValueContext: LuaValue,
) {
    private val resourceReferenceCache = HashMap<String, ResourceReference>()
    private val fourArgCtorCache = HashMap<Class<*>, Constructor<*>?>()
    private val threeArgCtorCache = HashMap<Class<*>, Constructor<*>?>()
    private val themeWrapperCache = HashMap<Int, Context>()

    private data class StyleSpec(
        val themeRes: Int = 0,
        val styleAttr: Int = 0,
        val styleRes: Int = 0,
    ) {
        val isEmpty: Boolean get() = themeRes == 0 && styleAttr == 0 && styleRes == 0
    }

    private enum class ResourceKind { ATTR, STYLE }

    private data class ResourceReference(val id: Int, val kind: ResourceKind)

    fun create(viewClass: LuaValue, layout: LuaValue): LuaValue {
        if (!hasStyleKeys(layout)) return viewClass.call(luaValueContext)

        val spec = parseStyleSpec(layout)
        if (spec.isEmpty) return viewClass.call(luaValueContext)

        val context = contextForTheme(spec.themeRes)
        val luaCtx = if (context === initialContext) luaValueContext else context.toLuaInstance()
        val clazz = viewClass.asJavaClassOrNull()
        val failures = ArrayList<String>(4)

        fun attempt(label: String, block: () -> LuaValue): LuaValue? =
            runCatching(block)
                .onFailure { e ->
                    failures += "$label -> ${e.message ?: e.javaClass.simpleName}"
                }
                .getOrNull()

        // 1) 标准四参：style 资源在第 4 参
        if (spec.styleRes != 0 && clazz != null) {
            fourArgCtor(clazz)?.let { ctor ->
                attempt("4-arg(styleAttr, styleRes)") {
                    ctor.newInstance(context, null, spec.styleAttr, spec.styleRes).toLuaInstance()
                }?.let { return it }
            }
        }

        // 2) style 资源作第三参（MaterialTextField：按 Widget_* 初始化 box + 内嵌 EditText）
        if (spec.styleRes != 0) {
            attempt("3-arg(styleRes)") {
                threeArg(viewClass, clazz, context, luaCtx, spec.styleRes)
            }?.let { return it }
        }

        // 3) 主题 attr 作第三参（?attr/textInputStyle 等）
        if (spec.styleAttr != 0) {
            attempt("3-arg(styleAttr)") {
                threeArg(viewClass, clazz, context, luaCtx, spec.styleAttr)
            }?.let { return it }
        }

        // 4) 回退
        attempt("1-arg(Context)") {
            viewClass.call(luaCtx)
        }?.let { return it }

        val idHint = layout["id"].let { if (it.isstring()) "[${it.asString()}] " else "" }
        throw LuaError(
            "loadlayout 构造 View 失败 $idHint$viewClass\n" +
                "theme=${layout["theme"]}, style=${layout["style"]}, " +
                "styleAttr=${layout["styleAttr"]}, styleRes=${layout["styleRes"]}\n" +
                "失败原因: ${failures.joinToString("; ").ifEmpty { "unknown" }}"
        )
    }

    private fun hasStyleKeys(layout: LuaValue): Boolean =
        !(layout["theme"].isnil() &&
            layout["styleAttr"].isnil() &&
            layout["styleRes"].isnil() &&
            layout["style"].isnil())

    private fun parseStyleSpec(layout: LuaValue): StyleSpec {
        val themeRes = resolve(layout["theme"], "theme").id
        val explicitAttr = resolve(layout["styleAttr"], "styleAttr").id
        val explicitRes = resolve(layout["styleRes"], "styleRes").id
        val legacy = resolve(layout["style"], "style")

        val styleAttr = when {
            explicitAttr != 0 -> explicitAttr
            legacy.id != 0 && legacy.kind == ResourceKind.ATTR -> legacy.id
            else -> 0
        }
        // 无 kind 的裸数字（MDC_R.style.xxx）算 style 资源
        val styleRes = when {
            explicitRes != 0 -> explicitRes
            legacy.id != 0 && legacy.kind == ResourceKind.STYLE -> legacy.id
            else -> 0
        }

        if (themeRes != 0 && looksLikeWidgetStyleName(layout["theme"])) {
            luaContext.sendMsg(
                "loadlayout: theme 疑似写成了 Widget style（应用 ContextThemeWrapper）。" +
                    "控件样式请用 style / styleRes，例如 MDC_R.style.Widget_Material3_TextInputLayout_OutlinedBox"
            )
        }
        return StyleSpec(themeRes, styleAttr, styleRes)
    }

    /** 粗检：theme 误写 Widget_* 时提示 */
    private fun looksLikeWidgetStyleName(value: LuaValue): Boolean {
        if (!value.isstring()) return false
        val s = value.asString()
        return s.contains("Widget_", ignoreCase = false) ||
            s.contains("TextInputLayout_", ignoreCase = false)
    }

    private fun contextForTheme(themeResId: Int): Context {
        if (themeResId == 0) return initialContext
        return themeWrapperCache.getOrPut(themeResId) {
            ContextThemeWrapper(initialContext, themeResId)
        }
    }

    private fun LuaValue.asJavaClassOrNull(): Class<*>? =
        if (isuserdata(Class::class.java)) touserdata(Class::class.java) as Class<*> else null

    private fun fourArgCtor(clazz: Class<*>): Constructor<*>? =
        fourArgCtorCache.getOrPut(clazz) {
            runCatching {
                clazz.getConstructor(
                    Context::class.java,
                    AttributeSet::class.java,
                    Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType,
                )
            }.getOrNull()
        }

    private fun threeArgCtor(clazz: Class<*>): Constructor<*>? =
        threeArgCtorCache.getOrPut(clazz) {
            runCatching {
                clazz.getConstructor(
                    Context::class.java,
                    AttributeSet::class.java,
                    Int::class.javaPrimitiveType,
                )
            }.getOrNull()
        }

    private fun threeArg(
        viewClass: LuaValue,
        clazz: Class<*>?,
        context: Context,
        luaCtx: LuaValue,
        third: Int,
    ): LuaValue {
        if (clazz != null) {
            threeArgCtor(clazz)?.let { ctor ->
                return ctor.newInstance(context, null, third).toLuaInstance()
            }
        }
        return viewClass.call(luaCtx, NIL, third.toLuaValue())
    }

    private fun inferKind(value: LuaValue, fieldName: String): ResourceKind {
        if (value.isstring()) {
            val ref = value.asString().trim()
            when {
                ref.startsWith("?") -> return ResourceKind.ATTR
                ref.startsWith("@attr/") || ref.startsWith("@android:attr/") ->
                    return ResourceKind.ATTR
                ref.startsWith("@style/") || ref.startsWith("@android:style/") ->
                    return ResourceKind.STYLE
            }
        }
        return if (fieldName == "styleAttr") ResourceKind.ATTR else ResourceKind.STYLE
    }

    /** Lua number / Java Number / 资源字符串 → id */
    private fun coerceToIntId(value: LuaValue): Int? {
        if (value.isnil()) return null
        if (value.isnumber()) return value.toint()
        if (value.isstring()) {
            val t = value.asString().trim()
            if (t.isEmpty() || t == "nil") return null
            t.toIntOrNull()?.let { return it }
            return null // 非纯数字字符串走 getIdentifier
        }
        if (value.isuserdata()) {
            val obj = value.touserdata(Any::class.java) ?: return null
            if (obj is Number) return obj.toInt()
        }
        return null
    }

    private fun resolve(value: LuaValue, fieldName: String): ResourceReference {
        val kind = inferKind(value, fieldName)
        if (value.isnil()) return ResourceReference(0, kind)

        // 数字 / Java Number 直接当资源 id（MDC_R.style.xxx、R.attr.xxx）
        coerceToIntId(value)?.let { id ->
            if (value.isstring() && value.asString().trim().toIntOrNull() == null) {
                // 字符串形式的非纯数字：下面 getIdentifier
            } else if (!value.isstring() || value.asString().trim().toIntOrNull() != null) {
                return ResourceReference(id, kind)
            }
        }

        if (!value.isstring()) {
            luaContext.sendMsg(
                "loadlayout: $fieldName 需要资源 id 或资源字符串，实际为 ${value.typename()}"
            )
            return ResourceReference(0, kind)
        }

        val ref = value.asString().trim()
        if (ref.isEmpty() || ref == "nil") return ResourceReference(0, kind)

        val cacheKey = "$fieldName|${kind.name}|$ref"
        resourceReferenceCache[cacheKey]?.let { return it }

        val resources = initialContext.resources
        val packageName = initialContext.packageName
        val normalized = when {
            ref.startsWith("?attr/") -> ref.removePrefix("?attr/")
            ref.startsWith("?android:attr/") -> "android:${ref.removePrefix("?android:attr/")}"
            ref.startsWith("?") -> ref.removePrefix("?")
            ref.startsWith("@") -> ref.removePrefix("@")
            else -> ref
        }

        val parts = normalized.split('/', limit = 2)
        val (typeName, entryName) = if (parts.size == 2) {
            parts[0] to parts[1]
        } else {
            val defaultType = if (kind == ResourceKind.ATTR) "attr" else "style"
            defaultType to normalized
        }

        val isAndroid = typeName.startsWith("android:")
        val cleanType = typeName.removePrefix("android:")
        val cleanName = entryName.removePrefix("android:")
        val resolved = resources.getIdentifier(
            cleanName, cleanType, if (isAndroid) "android" else packageName
        )
        if (resolved == 0) {
            // 再试 material 包名（部分环境 style 在依赖包）
            val materialId = if (!isAndroid && cleanType == "style") {
                resources.getIdentifier(cleanName, cleanType, "com.google.android.material")
            } else {
                0
            }
            if (materialId == 0) {
                luaContext.sendMsg("loadlayout: 无法解析 $fieldName 资源 '$ref'")
            }
            return ResourceReference(materialId, kind).also {
                resourceReferenceCache[cacheKey] = it
            }
        }
        return ResourceReference(resolved, kind).also {
            resourceReferenceCache[cacheKey] = it
        }
    }
}

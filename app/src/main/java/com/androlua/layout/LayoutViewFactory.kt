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
 */
internal class LayoutViewFactory(
    private val initialContext: Context,
    private val luaContext: LuaContext,
    private val luaValueContext: LuaValue,
) {
    private val resourceReferenceCache = HashMap<String, ResourceReference>()
    private val fourArgConstructorCache = HashMap<Class<*>, Constructor<*>?>()
    private val themeWrapperCache = HashMap<Int, Context>()

    private data class ViewStyleSpec(
        val themeResId: Int = 0,
        val styleAttr: Int = 0,
        val styleRes: Int = 0,
        val legacyStyleResId: Int = 0,
    ) {
        val hasStyle: Boolean
            get() = themeResId != 0 || styleAttr != 0 || styleRes != 0 || legacyStyleResId != 0
    }

    private enum class ResourceKind { ATTR, STYLE }

    private data class ResourceReference(val id: Int, val kind: ResourceKind)

    fun create(viewClass: LuaValue, layout: LuaValue): LuaValue {
        val themeRaw = layout["theme"]
        val styleAttrRaw = layout["styleAttr"]
        val styleResRaw = layout["styleRes"]
        val styleRaw = layout["style"]
        if (themeRaw.isnil() && styleAttrRaw.isnil() && styleResRaw.isnil() && styleRaw.isnil()) {
            return viewClass.call(luaValueContext)
        }

        val styleSpec = parseViewStyle(layout)
        if (!styleSpec.hasStyle) return viewClass.call(luaValueContext)

        // theme 只用于 ContextThemeWrapper；style / styleRes 不得当 theme 包一层
        val themedContext = contextForThemeRes(styleSpec.themeResId)
        val themedLuaContext =
            if (themedContext === initialContext) luaValueContext
            else themedContext.toLuaInstance()
        val attrs = NIL

        // 最终 defStyleRes：显式 styleRes 优先，否则 legacy style=@style/...
        val defStyleRes = when {
            styleSpec.styleRes != 0 -> styleSpec.styleRes
            styleSpec.legacyStyleResId != 0 -> styleSpec.legacyStyleResId
            else -> 0
        }
        val defStyleAttr = styleSpec.styleAttr

        var failures: ArrayList<String>? = null
        fun fail(sig: String, error: Throwable) {
            val list = failures ?: ArrayList<String>(4).also { failures = it }
            list.add("$sig -> ${error.message ?: error::class.java.simpleName}")
        }

        // 有 style 资源时优先四参 (Context, attrs, defStyleAttr, defStyleRes)
        // 纯 styleRes / @style 时 defStyleAttr=0，勿把 style id 塞进第三参
        if (defStyleRes != 0 && viewClass.isuserdata(Class::class.java)) {
            val clazz = viewClass.touserdata(Class::class.java) as Class<*>
            if (fourArgConstructor(clazz) != null) {
                try {
                    return instantiateView(
                        clazz, themedContext, null,
                        defStyleAttr, defStyleRes
                    )
                } catch (e: Exception) {
                    fail("(Context, AttributeSet?, defStyleAttr, defStyleRes)", e)
                }
            }
        }

        // 仅 styleAttr（?attr/…）走三参构造
        if (defStyleAttr != 0) {
            try {
                return viewClass.call(
                    themedLuaContext, attrs, defStyleAttr.toLuaValue()
                )
            } catch (e: Exception) {
                fail("(Context, AttributeSet?, defStyleAttr)", e)
            }
        }

        try {
            return viewClass.call(themedLuaContext)
        } catch (e: Exception) {
            fail("(Context)", e)
        }

        val viewId = layout["id"].let { if (it.isstring()) "[${it.asString()}] " else "" }
        throw LuaError(
            "loadlayout 构造 View 失败 $viewId$viewClass\n" +
                "theme=${layout["theme"]}, style=${layout["style"]}, " +
                "styleAttr=${layout["styleAttr"]}, styleRes=${layout["styleRes"]}\n" +
                "失败原因: ${failures?.joinToString("; ") ?: "unknown"}"
        )
    }

    private fun parseViewStyle(layout: LuaValue): ViewStyleSpec {
        val theme = layout["theme"]
        val styleAttrRaw = layout["styleAttr"]
        val styleResRaw = layout["styleRes"]
        val style = layout["style"]
        if (theme.isnil() && styleAttrRaw.isnil() && styleResRaw.isnil() && style.isnil()) {
            return ViewStyleSpec()
        }
        val themeResId = resolveResourceReference(theme, "theme").id
        val explicitStyleAttr = resolveResourceReference(styleAttrRaw, "styleAttr").id
        val explicitStyleRes = resolveResourceReference(styleResRaw, "styleRes").id
        val legacyStyleRef = resolveResourceReference(style, "style")
        val styleAttr = explicitStyleAttr.takeIf { it != 0 }
            ?: legacyStyleRef.id.takeIf { it != 0 && legacyStyleRef.kind == ResourceKind.ATTR }
            ?: 0
        val styleRes = explicitStyleRes.takeIf { it != 0 } ?: 0
        val legacyStyleResId =
            legacyStyleRef.id.takeIf { it != 0 && legacyStyleRef.kind == ResourceKind.STYLE } ?: 0
        return ViewStyleSpec(themeResId, styleAttr, styleRes, legacyStyleResId)
    }

    private fun contextForThemeRes(themeResId: Int): Context {
        if (themeResId == 0) return initialContext
        return themeWrapperCache.getOrPut(themeResId) {
            ContextThemeWrapper(initialContext, themeResId)
        }
    }

    private fun fourArgConstructor(clazz: Class<*>): Constructor<*>? {
        if (fourArgConstructorCache.containsKey(clazz)) {
            return fourArgConstructorCache[clazz]
        }
        val ctor = runCatching {
            clazz.getConstructor(
                Context::class.java,
                AttributeSet::class.java,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType
            )
        }.getOrNull()
        fourArgConstructorCache[clazz] = ctor
        return ctor
    }

    private fun instantiateView(
        clazz: Class<*>,
        context: Context,
        attrs: AttributeSet?,
        defStyleAttr: Int,
        defStyleRes: Int
    ): LuaValue {
        val constructor = fourArgConstructor(clazz)
            ?: throw NoSuchMethodException("${clazz.name}(Context, AttributeSet, int, int)")
        return constructor.newInstance(context, attrs, defStyleAttr, defStyleRes).toLuaInstance()
    }

    private fun inferResourceKind(value: LuaValue, fieldName: String): ResourceKind {
        if (value.isstring()) {
            val ref = value.asString().trim()
            if (ref.startsWith("?")) return ResourceKind.ATTR
            if (ref.startsWith("@attr/") || ref.startsWith("@android:attr/")) return ResourceKind.ATTR
            if (ref.startsWith("@style/") || ref.startsWith("@android:style/")) return ResourceKind.STYLE
        }
        return if (fieldName == "styleAttr") ResourceKind.ATTR else ResourceKind.STYLE
    }

    private fun resolveResourceReference(value: LuaValue, fieldName: String): ResourceReference {
        val kind = inferResourceKind(value, fieldName)
        if (value.isnil()) return ResourceReference(0, kind)
        if (value.isnumber()) return ResourceReference(value.toint(), kind)
        if (!value.isstring()) {
            luaContext.sendMsg(
                "loadlayout: $fieldName 需要资源 id 或资源字符串，实际为 ${value.typename()}"
            )
            return ResourceReference(0, kind)
        }

        val ref = value.asString().trim()
        if (ref.isEmpty() || ref == "nil") return ResourceReference(0, kind)
        ref.toIntOrNull()?.let { return ResourceReference(it, kind) }

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
            luaContext.sendMsg("loadlayout: 无法解析 $fieldName 资源 '$ref'")
        }
        return ResourceReference(resolved, kind).also {
            resourceReferenceCache[cacheKey] = it
        }
    }
}

package com.androlua.layout

import android.view.View
import android.widget.TextView
import com.google.android.material.textfield.TextInputLayout
import org.luaj.LuaError
import java.lang.reflect.Method
import java.util.concurrent.ConcurrentHashMap

/**
 * TextView 专用属性目标解析：
 * - 本控件是 TextView
 * - TextInputLayout / MaterialTextField：优先内部 EditText，否则反射代理 setter
 */
internal object LayoutTextSupport {

    private val NO_GET_EDIT_TEXT = Any()
    private val getEditTextCache = ConcurrentHashMap<Class<*>, Any>()

    fun resolve(host: View): TextView? {
        when (host) {
            is TextView -> return host
            is TextInputLayout -> {
                // 构造期 editText 可能尚未挂上；仍优先公开 API
                host.editText?.let { return it }
                return invokeGetEditText(host)
            }
        }
        return invokeGetEditText(host)
    }

    fun require(host: View, attr: String): TextView =
        resolve(host) ?: throw LuaError(
            "$attr 仅适用于 TextView 及其子类，或 TextInputLayout/MaterialTextField（内部 EditText），" +
                "实际为 ${host.javaClass.simpleName}"
        )

    fun setSingleLine(host: View, value: Boolean) {
        resolve(host)?.let {
            it.isSingleLine = value
            return
        }
        if (LayoutReflection.invokeBooleanSetter(host, "setSingleLine", value)) return
        throw unsupported(host, "singleLine")
    }

    fun setMaxLines(host: View, value: Int) {
        resolve(host)?.let {
            it.maxLines = value
            return
        }
        if (LayoutReflection.invokeIntSetter(host, "setMaxLines", value)) return
        throw unsupported(host, "maxLines")
    }

    fun setInputType(host: View, value: Int) {
        resolve(host)?.let {
            it.inputType = value
            return
        }
        if (LayoutReflection.invokeIntSetter(host, "setInputType", value)) return
        throw unsupported(host, "inputType")
    }

    fun setImeOptions(host: View, value: Int) {
        resolve(host)?.let {
            it.imeOptions = value
            return
        }
        if (LayoutReflection.invokeIntSetter(host, "setImeOptions", value)) return
        throw unsupported(host, "imeOptions")
    }

    fun setTextColor(host: View, color: Int) {
        resolve(host)?.let {
            // TextView.setTextColor(int) — 亦有 ColorStateList 重载，int 更常见于布局表
            it.setTextColor(color)
            return
        }
        // TextInputLayout：hint 用 setHintTextColor；正文色仍尽量落到内部 EditText
        if (host is TextInputLayout) {
            host.editText?.let {
                it.setTextColor(color)
                return
            }
        }
        if (LayoutReflection.invokeIntSetter(host, "setTextColor", color)) return
        throw unsupported(host, "textColor")
    }

    /**
     * TextInputLayout / MaterialTextField：hint 只设在外层（浮动标签），并清空内部 EditText.hint，
     * 避免「Layout 浮动 hint + EditText placeholder」叠成两个 Hint。
     */
    fun setHint(host: View, text: CharSequence?) {
        if (host is TextInputLayout) {
            host.hint = text
            host.editText?.hint = null
            invokeGetEditText(host)?.hint = null
            return
        }
        // 非标准 TIL 子类：若有 getEditText，同样只写外层
        val inner = invokeGetEditText(host)
        if (inner != null) {
            if (LayoutReflection.trySetJavaValue(host, "hint", text)) {
                inner.hint = null
                return
            }
            // 外层无 hint 再落到内部
            inner.hint = text
            return
        }
        resolve(host)?.let {
            it.hint = text
            return
        }
        if (LayoutReflection.trySetJavaValue(host, "hint", text)) return
        throw unsupported(host, "hint")
    }

    fun setHintTextColor(host: View, color: Int) {
        // TextInputLayout 公开 API：hint 颜色（与内部 EditText hint 不同层）
        if (host is TextInputLayout) {
            runCatching {
                host.setHintTextColor(android.content.res.ColorStateList.valueOf(color))
                return
            }
            runCatching {
                host.defaultHintTextColor = android.content.res.ColorStateList.valueOf(color)
                return
            }
        }
        resolve(host)?.let {
            it.setHintTextColor(color)
            return
        }
        if (LayoutReflection.invokeIntSetter(host, "setHintTextColor", color)) return
        throw unsupported(host, "hintTextColor")
    }

    fun setTextSizePx(host: View, px: Float) {
        resolve(host)?.let {
            it.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, px)
            return
        }
        val m = LayoutReflection.cachedMethod(
            LayoutReflection.floatSetterCache(),
            host.javaClass,
            "setTextSize",
            Int::class.javaPrimitiveType!!,
            Float::class.javaPrimitiveType!!
        )
        if (m != null) {
            m.invoke(host, android.util.TypedValue.COMPLEX_UNIT_PX, px)
            return
        }
        if (LayoutReflection.invokeFloatSetter(host, "setTextSize", px)) return
        throw unsupported(host, "textSize")
    }

    fun setLineSpacingMultiplier(host: View, mult: Float) {
        resolve(host)?.let {
            it.setLineSpacing(it.lineSpacingExtra, mult)
            return
        }
        if (invokeLineSpacing(host, 0f, mult)) return
        throw unsupported(host, "lineSpacingMultiplier")
    }

    fun setLineSpacingExtra(host: View, extraPx: Float) {
        resolve(host)?.let {
            it.setLineSpacing(extraPx, it.lineSpacingMultiplier)
            return
        }
        if (invokeLineSpacing(host, extraPx, 1f)) return
        throw unsupported(host, "lineSpacingExtra")
    }

    fun setEllipsize(host: View, at: android.text.TextUtils.TruncateAt) {
        resolve(host)?.let {
            it.ellipsize = at
            return
        }
        val m = LayoutReflection.cachedMethod(
            LayoutReflection.objectSetterCache(),
            host.javaClass,
            "setEllipsize",
            android.text.TextUtils.TruncateAt::class.java
        )
        if (m != null) {
            m.invoke(host, at)
            return
        }
        throw unsupported(host, "ellipsize")
    }

    fun setTypeface(host: View, typeface: android.graphics.Typeface) {
        resolve(host)?.let {
            it.typeface = typeface
            return
        }
        val m = LayoutReflection.cachedMethod(
            LayoutReflection.objectSetterCache(),
            host.javaClass,
            "setTypeface",
            android.graphics.Typeface::class.java
        )
        if (m != null) {
            m.invoke(host, typeface)
            return
        }
        throw unsupported(host, "textStyle")
    }

    private fun invokeGetEditText(host: View): TextView? {
        val clazz = host.javaClass
        val cached = getEditTextCache[clazz]
        if (cached === NO_GET_EDIT_TEXT) return null
        val method = if (cached is Method) {
            cached
        } else {
            val found = runCatching {
                clazz.methods.firstOrNull {
                    it.name == "getEditText" && it.parameterTypes.isEmpty()
                }
            }.getOrNull()
            if (found == null) {
                getEditTextCache[clazz] = NO_GET_EDIT_TEXT
                return null
            }
            getEditTextCache[clazz] = found
            found
        }
        return runCatching { method.invoke(host) as? TextView }.getOrNull()
    }

    private fun invokeLineSpacing(host: View, extra: Float, mult: Float): Boolean {
        val m = LayoutReflection.cachedMethod(
            LayoutReflection.floatSetterCache(),
            host.javaClass,
            "setLineSpacing",
            Float::class.javaPrimitiveType!!,
            Float::class.javaPrimitiveType!!
        ) ?: return false
        return runCatching {
            m.invoke(host, extra, mult)
            true
        }.getOrDefault(false)
    }

    private fun unsupported(host: View, attr: String): LuaError = LuaError(
        "$attr 仅适用于 TextView 及其子类，或 TextInputLayout/MaterialTextField，" +
            "实际为 ${host.javaClass.simpleName}"
    )
}

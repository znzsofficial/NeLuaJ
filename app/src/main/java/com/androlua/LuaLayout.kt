package com.androlua

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.text.InputFilter
import android.text.TextUtils
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.Checkable
import android.widget.ImageView
import android.widget.ImageView.ScaleType
import android.widget.ListView
import android.widget.TextView
import androidx.core.view.ViewCompat
import com.androlua.adapter.ArrayListAdapter
import com.androlua.adapter.LuaAdapter
import com.androlua.layout.LayoutEnums
import com.androlua.layout.LayoutParamsApplier
import com.androlua.layout.LayoutReflection
import com.androlua.layout.LayoutSrcLoader
import com.androlua.layout.LayoutTextSupport
import com.androlua.layout.LayoutTint
import com.androlua.layout.LayoutValueParser
import com.androlua.layout.LayoutViewFactory
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.isNotNil
import com.nekolaska.ktx.require
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import github.daisukiKaffuChino.LuaPagerAdapter
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.LuaValue.NIL
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceLuaToJava
import java.util.Locale

fun LuaValue.toView(): View = this.touserdata(View::class.java)

/**
 * 表驱动布局加载器。实现拆在 [com.androlua.layout]：
 * - [LayoutEnums] / [LayoutValueParser] / [LayoutViewFactory]
 * - [LayoutParamsApplier] layout_* · margin · padding · 嵌套 LP 类
 * - [LayoutSrcLoader] src / @drawable
 * - [LayoutTint] / [LayoutTextSupport] / [LayoutReflection]
 */
class LuaLayout(private val initialContext: Context) {
    private val dm = initialContext.resources.displayMetrics
    private val views = HashMap<String, LuaValue>()
    private val ids = HashMap<String, Int>()
    private val luaValueContext: LuaValue = initialContext.toLuaInstance()
    private val luaContext = luaValueContext.touserdata(LuaContext::class.java)
    private val scaleTypeValues: Array<ScaleType> = ScaleType.entries.toTypedArray()

    private val values = LayoutValueParser(initialContext, luaContext, dm)
    private val viewFactory = LayoutViewFactory(initialContext, luaContext, luaValueContext)
    private val paramsApplier = LayoutParamsApplier(luaContext, values, ids)
    private val srcLoader = LayoutSrcLoader(initialContext, luaContext)

    val id: Map<String, Int> get() = ids
    val view: Map<String, LuaValue> get() = views

    fun type(): Int = LuaValue.TUSERDATA
    fun typename(): String = "LuaLayout"
    fun get(key: LuaValue): LuaValue? = views[key.asString()]
    fun get(key: String): LuaValue? = views[key]

    fun parseColor(colorString: String): Int = values.parseColor(colorString)

    private fun getOrGenerateId(idString: String): Int =
        ids.getOrPut(idString) { View.generateViewId() }

    private fun processLuaPages(viewsTable: LuaTable, env: LuaTable): List<View> {
        val viewList = mutableListOf<View>()
        for (i in 1..viewsTable.length()) {
            val v = viewsTable[i]
            val page = when {
                v.isuserdata() -> v.toView()
                v.istable() -> load(v.checktable(), env).toView()
                v.isstring() -> load(luaContext.luaState.require(v), env).toView()
                else -> throw LuaError(
                    "Unsupported type for Lua pages: ${v.typename()}. Expected userdata, table, or string."
                )
            }
            viewList.add(page)
        }
        return viewList
    }

    @JvmOverloads
    fun load(
        layout: LuaValue,
        env: LuaTable = LuaTable(),
        params: LuaValue = ViewGroup.LayoutParams::class.java.toLuaValue()
    ): LuaValue {
        var lp = params
        val viewClass = layout[1]
        if (viewClass.isnil()) {
            val idHint = layout["id"].let {
                if (it.isstring()) " (id=\"${it.asString()}\")" else ""
            }
            throw LuaError(
                "loadlayout error: 布局表的第一个值必须是一个 View 类$idHint。\n" +
                    "请检查是否遗漏了 import 语句，或者类名拼写是否正确。\n" +
                    "布局表内容: ${layout.checktable().dump()}"
            )
        }
        val view = viewFactory.create(viewClass, layout)
        // 仅 ViewGroup 嵌套 LP 类；勿用 viewClass["LayoutParams"]（叶子会误调 getLayoutParams）
        val childLayoutParamsClass =
            LayoutParamsApplier.resolveNestedLayoutParamsLua(viewClass)
        lp = lp.call(LayoutEnums.wrapContent, LayoutEnums.wrapContent)
        // 首遍收集 margin/padding 原值，结束时一次应用（不再二次 layout["…"]）
        val box = LayoutParamsApplier.Box()
        try {
            var key = NIL
            var next: Varargs
            while (!layout.next(key).also { next = it }.firstArg().isnil()) {
                try {
                    key = next.firstArg()
                    if (key.isint()) {
                        if (key.toint() > 1) {
                            addChild(
                                view, viewClass, next.secondArg(), env, childLayoutParamsClass
                            )
                        }
                    } else if (key.isstring()) {
                        val keyString = key.asString()
                        val value = next.secondArg()
                        box.accept(keyString, value)
                        applyAttribute(
                            keyString, value, view, viewClass, env, lp, key
                        )
                    }
                } catch (e: LuaError) {
                    reportAttrError(layout, viewClass, next, e)
                } catch (e: Exception) {
                    reportAttrError(layout, viewClass, next, e)
                }
            }

            if (box.hasMargin) {
                try {
                    paramsApplier.applyMargins(box, lp)
                } catch (e: Exception) {
                    luaContext.sendError("loadlayout margin 解析错误 ${layoutIdTag(layout)}", e)
                }
            }

            assignLayoutParams(view, lp)
            if (box.hasPadding) {
                try {
                    paramsApplier.applyPadding(box, view.toView())
                } catch (e: Exception) {
                    luaContext.sendError("loadlayout padding 解析错误 ${layoutIdTag(layout)}", e)
                }
            }
        } catch (e: Exception) {
            luaContext.sendError("loadlayout 布局错误 ${layoutIdTag(layout)}", e)
        }
        return view
    }

    private fun layoutIdTag(layout: LuaValue): String {
        val id = layout["id"]
        return if (id.isstring()) "[${id.asString()}]" else ""
    }

    /** 将 Lua LayoutParams userdata 直接挂到 View，失败再走桥 */
    private fun assignLayoutParams(view: LuaValue, lp: LuaValue) {
        val host = try {
            view.toView()
        } catch (_: Exception) {
            null
        }
        if (host != null) {
            val raw = try {
                lp.touserdata()
            } catch (_: Exception) {
                null
            }
            if (raw is ViewGroup.LayoutParams) {
                host.layoutParams = raw
                return
            }
        }
        view["LayoutParams"] = lp
    }

    private fun reportAttrError(
        layout: LuaValue,
        viewClass: LuaValue,
        next: Varargs,
        e: Exception
    ) {
        val viewId = layout["id"].let {
            if (it.isstring()) it.asString() else viewClass.toString()
        }
        val root = e as? Throwable ?: return
        val cause = root.cause
        val detail = buildString {
            append(root.message ?: root.javaClass.simpleName)
            if (cause != null && cause !== root) {
                append(" | cause: ")
                append(cause.message ?: cause.javaClass.simpleName)
            }
        }
        luaContext.sendError(
            "loadlayout 属性错误 [$viewId] ${next.firstArg()}=${next.secondArg()}: $detail",
            e
        )
    }

    private fun addChild(
        parent: LuaValue,
        parentClass: LuaValue,
        childRaw: LuaValue,
        env: LuaTable,
        layoutParamsClass: LuaValue =
            LayoutParamsApplier.resolveNestedLayoutParamsLua(parentClass),
    ) {
        var child = childRaw
        if (child.isnil()) return
        if (child.isstring()) {
            child = runCatching { luaContext.luaState.require(child) }.getOrElse {
                throw LuaError("无法 require 子布局: ${childRaw.asString()} — ${it.message}")
            }
        }
        val parentJavaClass = if (parentClass.isuserdata(Class::class.java)) {
            parentClass.touserdata(Class::class.java) as Class<*>
        } else {
            null
        }
        if (parentJavaClass != null &&
            AdapterView::class.java.isAssignableFrom(parentJavaClass)
        ) {
            if (!child.istable()) {
                throw LuaError("AdapterView 子项需要布局表，实际为 ${child.typename()}")
            }
            parent.jset("adapter", LuaAdapter(luaContext, child.checktable()))
            return
        }
        if (!child.istable() && !child.isuserdata()) {
            throw LuaError(
                "子节点需要布局表 / View userdata / 布局路径字符串，实际为 ${child.typename()}"
            )
        }
        val childView = if (child.isuserdata()) {
            child
        } else {
            if (layoutParamsClass.isnil()) load(child, env) else load(child, env, layoutParamsClass)
        }
        // ViewGroup 热路径：直接 addView，少一次 parent["addView"] 桥查找
        val host = try {
            parent.toView()
        } catch (_: Exception) {
            null
        }
        if (host is ViewGroup) {
            val childHost = try {
                childView.toView()
            } catch (_: Exception) {
                null
            }
            if (childHost != null) {
                host.addView(childHost)
                return
            }
        }
        val addView = parent["addView"]
        if (addView.isnil()) {
            throw LuaError(
                "父控件无法 addView（${parentClass} 可能不是 ViewGroup）"
            )
        }
        addView.call(childView)
    }

    private fun applyAttribute(
        keyString: String,
        rawValue: LuaValue,
        view: LuaValue,
        viewClass: LuaValue,
        env: LuaTable,
        params: LuaValue,
        key: LuaValue
    ) {
        var tValue = rawValue

        when (keyString) {
            "style", "styleAttr", "styleRes", "theme" -> return
            "padding", "paddingLeft", "paddingTop", "paddingRight",
            "paddingBottom", "paddingStart", "paddingEnd" -> return

            "id" -> {
                val name = tValue.asString().trim()
                if (name.isEmpty()) throw LuaError("id 不能为空字符串")
                val viewId = getOrGenerateId(name)
                // 直设 View id，避免 view["id"]= 桥
                try {
                    view.toView().id = viewId
                } catch (_: Exception) {
                    view["id"] = viewId
                }
                views[name] = view
                env[tValue] = view
                return
            }

            "text" -> {
                val host = view.toView()
                val s = if (tValue.isstring() || tValue.isnumber()) {
                    tValue.asString()
                } else {
                    tValue.tostring().asString()
                }
                val tv = LayoutTextSupport.resolve(host)
                if (tv != null) {
                    tv.text = s
                } else if (!LayoutReflection.trySetJavaValue(host, "text", s)) {
                    view["text"] = tValue.tostring()
                }
                return
            }

            "textSize" -> {
                val px = when {
                    tValue.isnumber() -> TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_SP, tValue.todouble().toFloat(), dm
                    )
                    tValue.isstring() -> {
                        val s = tValue.asString().trim()
                        val parsed = values.toValue(s, "textSize")
                        when (parsed) {
                            is Number -> {
                                if (s.toFloatOrNull() != null &&
                                    !s.endsWith("sp") && !s.endsWith("dp") &&
                                    !s.endsWith("px") && !s.endsWith("pt") &&
                                    !s.endsWith("in") && !s.endsWith("mm")
                                ) {
                                    TypedValue.applyDimension(
                                        TypedValue.COMPLEX_UNIT_SP, parsed.toFloat(), dm
                                    )
                                } else parsed.toFloat()
                            }
                            else -> throw LuaError("无法解析 textSize: $s")
                        }
                    }
                    else -> throw LuaError("textSize 需要 number 或尺寸字符串")
                }
                LayoutTextSupport.setTextSizePx(view.toView(), px)
                return
            }

            "textStyle" -> {
                val style = when (tValue.asString().lowercase(Locale.ROOT)) {
                    "bold" -> Typeface.BOLD
                    "normal" -> Typeface.NORMAL
                    "italic" -> Typeface.ITALIC
                    "italic|bold", "bold|italic", "bold_italic", "bolditalic" ->
                        Typeface.BOLD_ITALIC
                    else -> throw LuaError(
                        "Unsupported textStyle: ${tValue.asString()}（可用: normal/bold/italic/bold|italic）"
                    )
                }
                LayoutTextSupport.setTypeface(view.toView(), Typeface.defaultFromStyle(style))
                return
            }

            "scaleType" -> {
                val raw = tValue.asString().trim()
                val key = raw.lowercase(Locale.ROOT).replace('-', '_')
                val idx = LayoutEnums.scaleType[raw]
                    ?: LayoutEnums.scaleType[key]
                    ?: throw LuaError(
                        "不支持的 scaleType: $raw（可用: matrix/fitXY/fitStart/fitCenter/fitEnd/center/centerCrop/centerInside）"
                    )
                if (idx !in scaleTypeValues.indices) {
                    throw LuaError("scaleType 内部下标越界: $idx")
                }
                val st = scaleTypeValues[idx]
                val host = view.toView()
                if (host is ImageView) {
                    host.scaleType = st
                } else {
                    throw LuaError(
                        "scaleType 仅适用于 ImageView，实际为 ${host.javaClass.simpleName}"
                    )
                }
                return
            }

            "ellipsize" -> {
                val name = tValue.asString().uppercase(Locale.ROOT)
                val at = runCatching { TextUtils.TruncateAt.valueOf(name) }.getOrElse {
                    throw LuaError(
                        "不支持的 ellipsize: ${tValue.asString()}（可用: START/END/MIDDLE/MARQUEE）"
                    )
                }
                LayoutTextSupport.setEllipsize(view.toView(), at)
                return
            }

            "hint" -> {
                val host = view.toView()
                val s = if (tValue.isstring() || tValue.isnumber()) {
                    tValue.asString()
                } else {
                    tValue.tostring().asString()
                }
                // TextInputLayout：只设外层浮动 hint，勿落到内部 EditText（否则双 Hint）
                runCatching {
                    LayoutTextSupport.setHint(host, s)
                }.onFailure {
                    if (!LayoutReflection.trySetJavaValue(host, "hint", s)) {
                        view["hint"] = tValue.tostring()
                    }
                }
                return
            }

            "enabled" -> {
                view.toView().isEnabled = values.toBoolean(tValue)
                return
            }
            "selected" -> {
                view.toView().isSelected = values.toBoolean(tValue)
                return
            }
            "clickable" -> {
                view.toView().isClickable = values.toBoolean(tValue)
                return
            }
            "focusable" -> {
                view.toView().isFocusable = values.toBoolean(tValue)
                return
            }
            "alpha" -> {
                val a = when {
                    tValue.isnumber() -> tValue.todouble().toFloat()
                    tValue.isstring() -> tValue.asString().toFloatOrNull()
                        ?: throw LuaError("无法解析 alpha: ${tValue.asString()}")
                    else -> throw LuaError("alpha 需要 number")
                }
                view.toView().alpha = a
                return
            }

            "textColor", "TextColor" -> {
                LayoutTextSupport.setTextColor(view.toView(), values.toColorIntValue(tValue))
                return
            }

            "hintTextColor", "HintTextColor", "textColorHint", "TextColorHint" -> {
                LayoutTextSupport.setHintTextColor(
                    view.toView(), values.toColorIntValue(tValue)
                )
                return
            }

            "BackgroundColor", "backgroundColor" -> {
                view.toView().setBackgroundColor(values.toColorIntValue(tValue))
                return
            }

            "BackgroundTintList", "backgroundTintList", "backgroundTint" -> {
                val csl = values.toColorStateList(tValue)
                val v = view.toView()
                when (v) {
                    is MaterialButton -> v.backgroundTintList = csl
                    else -> ViewCompat.setBackgroundTintList(v, csl)
                }
                return
            }

            // MaterialButton / FAB 等：int / "#AARRGGBB" / ?attr / ColorStateList → ColorStateList
            // 切勿走默认 Java setter：setIconTint 要 ColorStateList，int 会 IllegalArgumentException
            "iconTint", "IconTint", "iconTintList", "IconTintList" -> {
                val host = view.toView()
                val csl = try {
                    values.toColorStateList(tValue)
                } catch (e: LuaError) {
                    throw LuaError(
                        "iconTint 颜色无效（${host.javaClass.simpleName}）: ${e.message}"
                    )
                }
                if (!LayoutTint.applyIconTint(host, csl)) {
                    throw LuaError(
                        "iconTint 无法应用到 ${host.javaClass.simpleName}：" +
                            "需要 MaterialButton / FAB / Chip / ImageView / TextInputLayout 或带 setIconTint(ColorStateList) 的控件"
                    )
                }
                return
            }

            "TintColor", "tintColor" -> {
                LayoutTint.apply(view.toView(), values.toColorStateList(tValue))
                return
            }

            "dividerHeight", "DividerHeight" -> {
                val px = values.toLayoutSize(tValue)
                val v = view.toView()
                if (v is ListView) {
                    v.dividerHeight = px
                } else {
                    throw LuaError(
                        "dividerHeight 仅适用于 ListView，实际为 ${v.javaClass.simpleName}（RecyclerView 请删除该属性）"
                    )
                }
                return
            }

            "strokeColor", "StrokeColor" -> {
                // CardView: setStrokeColor(int)；MaterialButton/Chip: ColorStateList
                val csl = values.toColorStateList(tValue)
                val color = csl.defaultColor
                val v = view.toView()
                when (v) {
                    is MaterialCardView -> {
                        // API 有 int 与 ColorStateList 重载；int 兼容更广
                        v.strokeColor = color
                    }
                    is MaterialButton -> v.strokeColor = csl
                    is Chip -> v.chipStrokeColor = csl
                    else -> {
                        val mCsl = LayoutReflection.cachedMethod(
                            LayoutReflection.colorStateListSetterCache(), v.javaClass,
                            "setStrokeColor", ColorStateList::class.java
                        )
                        if (mCsl != null) {
                            mCsl.invoke(v, csl)
                        } else {
                            val mInt = LayoutReflection.cachedMethod(
                                LayoutReflection.intSetterCache(), v.javaClass, "setStrokeColor",
                                Int::class.javaPrimitiveType!!
                            )
                            if (mInt != null) {
                                mInt.invoke(v, color)
                            } else {
                                throw LuaError(
                                    "strokeColor 需要 MaterialCardView / MaterialButton / Chip，实际为 ${v.javaClass.simpleName}"
                                )
                            }
                        }
                    }
                }
                return
            }

            "strokeWidth", "StrokeWidth" -> {
                val px = values.toDimensionPx(tValue)
                val pxInt = px.toInt()
                val v = view.toView()
                when (v) {
                    is MaterialCardView -> v.strokeWidth = pxInt
                    is MaterialButton -> v.strokeWidth = pxInt
                    is Chip -> v.chipStrokeWidth = px
                    else -> {
                        val m = LayoutReflection.cachedMethod(
                            LayoutReflection.intSetterCache(), v.javaClass, "setStrokeWidth",
                            Int::class.javaPrimitiveType!!
                        )
                        if (m != null) {
                            m.invoke(v, pxInt)
                        } else if (!LayoutReflection.invokeFloatSetter(v, "setStrokeWidth", px)) {
                            throw LuaError(
                                "strokeWidth 需要 MaterialCardView / MaterialButton / Chip，实际为 ${v.javaClass.simpleName}"
                            )
                        }
                    }
                }
                return
            }

            "items" -> {
                val adapter = view["adapter"]
                if (adapter.isNotNil()) {
                    adapter["addAll"].call(tValue)
                } else {
                    view["setAdapter"].jcall(
                        ArrayListAdapter(
                            initialContext,
                            android.R.layout.simple_list_item_1,
                            CoerceLuaToJava.arrayCoerce(tValue, String::class.java) as Array<*>
                        )
                    )
                }
                return
            }

            "minHeight" -> {
                view.toView().minimumHeight = values.toDimensionPx(tValue).toInt()
                return
            }
            "minWidth" -> {
                view.toView().minimumWidth = values.toDimensionPx(tValue).toInt()
                return
            }

            "pages" -> {
                val viewList = processLuaPages(tValue.checktable(), env)
                val pagerAdapter = LuaPagerAdapter()
                pagerAdapter.setData(viewList)
                view["setAdapter"].jcall(pagerAdapter)
                return
            }

            "pagesWithTitle" -> {
                val table = tValue.checktable()
                val viewList = processLuaPages(table[1].checktable(), env)
                val titlesTable = table[2].checktable()
                val titleList = mutableListOf<String>()
                for (i in 1..titlesTable.length()) {
                    titleList.add(titlesTable[i].asString())
                }
                val pagerAdapter = LuaPagerAdapter()
                pagerAdapter.setData(viewList, titleList)
                view["setAdapter"].jcall(pagerAdapter)
                return
            }

            "src" -> {
                srcLoader.apply(tValue, view.toView(), view)
                return
            }

            "background" -> {
                when {
                    tValue.isuserdata(Drawable::class.java) ->
                        view.jset("background", tValue.touserdata(Drawable::class.java))
                    tValue.isuserdata(Bitmap::class.java) -> {
                        val bmp = tValue.touserdata(Bitmap::class.java) as Bitmap
                        view.jset(
                            "background",
                            android.graphics.drawable.BitmapDrawable(
                                initialContext.resources, bmp
                            )
                        )
                    }
                    tValue.isnumber() ->
                        view.jset("backgroundColor", tValue.toint())
                    tValue.isstring() -> {
                        val str = tValue.asString().trim()
                        when {
                            str.isEmpty() -> { /* ignore */ }
                            str.startsWith("#") || str.startsWith("?") ->
                                view.toView().setBackgroundColor(values.toColorIntValue(tValue))
                            else -> view.jset(
                                "background",
                                LuaBitmapDrawable(luaContext, str)
                            )
                        }
                    }
                    else -> throw LuaError(
                        "background 需要 Drawable / Bitmap / 颜色 / 路径字符串，实际为 ${tValue.typename()}"
                    )
                }
                return
            }

            "visibility" -> {
                val v = when {
                    tValue.isnumber() -> tValue.toint()
                    tValue.isboolean() -> if (tValue.toboolean()) View.VISIBLE else View.GONE
                    tValue.isstring() -> values.toIntValue(tValue, "visibility")
                    else -> throw LuaError(
                        "visibility 需要 \"visible\"/\"invisible\"/\"gone\"、int 或 boolean"
                    )
                }
                view.toView().visibility = v
                return
            }

            "singleLine" -> {
                LayoutTextSupport.setSingleLine(view.toView(), values.toBoolean(tValue))
                return
            }
            "maxLines" -> {
                LayoutTextSupport.setMaxLines(view.toView(), values.toIntValue(tValue))
                return
            }
            "maxLength" -> {
                val n = values.toIntValue(tValue)
                if (n < 0) throw LuaError("maxLength 不能为负")
                val host = view.toView()
                val tv = LayoutTextSupport.resolve(host)
                if (tv != null) {
                    val filters = tv.filters?.filterNot { it is InputFilter.LengthFilter }
                        ?.toMutableList() ?: mutableListOf()
                    filters.add(InputFilter.LengthFilter(n))
                    tv.filters = filters.toTypedArray()
                } else if (!LayoutReflection.invokeIntSetter(host, "setMaxLength", n)) {
                    throw LuaError(
                        "maxLength 仅适用于 TextView / MaterialTextField，实际为 ${host.javaClass.simpleName}"
                    )
                }
                return
            }
            "inputType" -> {
                LayoutTextSupport.setInputType(
                    view.toView(), values.toIntValue(tValue, "inputType")
                )
                return
            }
            "imeOptions" -> {
                LayoutTextSupport.setImeOptions(
                    view.toView(), values.toIntValue(tValue, "imeOptions")
                )
                return
            }
            "lineSpacingMultiplier" -> {
                val mult = when {
                    tValue.isnumber() -> tValue.todouble().toFloat()
                    tValue.isstring() -> tValue.asString().toFloatOrNull()
                        ?: throw LuaError("无法解析 lineSpacingMultiplier: ${tValue.asString()}")
                    else -> throw LuaError("lineSpacingMultiplier 需要 number")
                }
                LayoutTextSupport.setLineSpacingMultiplier(view.toView(), mult)
                return
            }
            "lineSpacingExtra" -> {
                LayoutTextSupport.setLineSpacingExtra(
                    view.toView(), values.toDimensionPx(tValue)
                )
                return
            }
            "elevation" -> {
                view.toView().elevation = values.toDimensionPx(tValue)
                return
            }
            "CardBackgroundColor", "cardBackgroundColor" -> {
                val color = values.toColorIntValue(tValue)
                val v = view.toView()
                if (v is MaterialCardView) v.setCardBackgroundColor(color)
                else v.setBackgroundColor(color)
                return
            }
            "cardElevation", "CardElevation" -> {
                val px = values.toDimensionPx(tValue)
                val v = view.toView()
                if (v is MaterialCardView) v.cardElevation = px else v.elevation = px
                return
            }
            "gravity" -> {
                val g = values.toIntValue(tValue, "gravity")
                val v = view.toView()
                if (LayoutReflection.invokeIntSetter(v, "setGravity", g)) return
                // TextInputLayout 等：落到内部 EditText
                val tv = LayoutTextSupport.resolve(v)
                if (tv != null && LayoutReflection.invokeIntSetter(tv, "setGravity", g)) return
                throw LuaError(
                    "gravity 需要 setGravity(int)（如 TextView、LinearLayout），实际为 ${v.javaClass.simpleName}"
                )
            }
            "radius", "cornerRadius" -> {
                val px = values.toDimensionPx(tValue)
                val v = view.toView()
                if (v is MaterialCardView) {
                    v.radius = px
                } else if (!LayoutReflection.invokeFloatSetter(v, "setRadius", px)) {
                    throw LuaError(
                        "radius/cornerRadius 需要 MaterialCardView 或 setRadius(float)，实际为 ${v.javaClass.simpleName}"
                    )
                }
                return
            }
            "Checked", "checked" -> {
                val on = values.toBoolean(tValue)
                val v = view.toView()
                when (v) {
                    is Checkable -> v.isChecked = on
                    else -> {
                        if (!LayoutReflection.invokeBooleanSetter(v, "setChecked", on)) {
                            throw LuaError(
                                "Checked 需要实现 Checkable 或提供 setChecked(boolean)，实际为 ${v.javaClass.simpleName}"
                            )
                        }
                    }
                }
                return
            }
            "checkable", "Checkable" -> {
                val on = values.toBoolean(tValue)
                val v = view.toView()
                when (v) {
                    is Chip -> v.isCheckable = on
                    is MaterialCardView -> v.isCheckable = on
                    is MaterialButton -> v.isCheckable = on
                    else -> {
                        if (!LayoutReflection.invokeBooleanSetter(v, "setCheckable", on)) {
                            throw LuaError(
                                "checkable 需要 setCheckable(boolean)，实际为 ${v.javaClass.simpleName}"
                            )
                        }
                    }
                }
                return
            }

            else -> if (keyString.startsWith("on")) {
                if (tValue.isstring()) {
                    val finalVal = tValue
                    tValue = object : VarArgFunction() {
                        override fun invoke(args: Varargs): Varargs {
                            return env[finalVal].invoke(args)
                        }
                    }
                }
                view[key] = tValue
                return
            }
        }

        // layout_* 仍可能要字符串尺寸/枚举；先处理 layout 再做默认 setter，少一次无用转换
        if (keyString.startsWith("layout")) {
            if (tValue.type() == LuaValue.TSTRING) {
                tValue = values.toValue(tValue.asString(), keyString).toLuaValue()
            }
            paramsApplier.applyLayoutParam(keyString, tValue, params)
            return
        }

        val viewObj = try {
            view.toView()
        } catch (_: Exception) {
            null
        }
        if (viewObj != null) {
            // 热路径：可写属性才直调缓存 Method；失败再走 view[key]= 桥
            if (tryApplyJavaProperty(viewObj, keyString, tValue, rawValue)) return

            if (LayoutReflection.canSetJavaProperty(viewObj.javaClass, keyString)) {
                if (tValue.type() == LuaValue.TSTRING) {
                    tValue = values.toValue(tValue.asString(), keyString).toLuaValue()
                }
                view[key] = tValue
                return
            }
            // TextInputLayout / MaterialTextField：外层无 setter 时回退内部 EditText
            val inner = LayoutTextSupport.resolve(viewObj)
            if (inner != null && inner !== viewObj) {
                if (tryApplyJavaProperty(inner, keyString, tValue, rawValue)) return
                if (LayoutReflection.canSetJavaProperty(inner.javaClass, keyString)) {
                    try {
                        if (tValue.type() == LuaValue.TSTRING) {
                            tValue = values.toValue(tValue.asString(), keyString).toLuaValue()
                        }
                        view[key] = tValue
                        return
                    } catch (_: Exception) {
                        when (keyString) {
                            "enabled" -> {
                                inner.isEnabled = values.toBoolean(rawValue)
                                return
                            }
                            "selected" -> {
                                inner.isSelected = values.toBoolean(rawValue)
                                return
                            }
                            "clickable" -> {
                                inner.isClickable = values.toBoolean(rawValue)
                                return
                            }
                            "focusable" -> {
                                inner.isFocusable = values.toBoolean(rawValue)
                                return
                            }
                        }
                    }
                }
            }
            val setterHint = LayoutReflection.setterName(keyString)
            throw LuaError(
                "不支持的属性 '$keyString'（${viewObj.javaClass.simpleName} 无 $setterHint / field）"
            )
        }
        if (tValue.type() == LuaValue.TSTRING) {
            tValue = values.toValue(tValue.asString(), keyString).toLuaValue()
        }
        view[key] = tValue
    }

    /**
     * 默认属性：优先反射 setter（int/float/boolean/CSL/CharSequence），减少 Lua↔Java 往返。
     * 必须先通过 [LayoutReflection.canSetJavaProperty]，避免对不存在的属性误命中其它 setXxx。
     */
    private fun tryApplyJavaProperty(
        host: View,
        keyString: String,
        tValue: LuaValue,
        rawValue: LuaValue,
    ): Boolean {
        if (!LayoutReflection.canSetJavaProperty(host.javaClass, keyString)) {
            return false
        }
        when {
            tValue.isboolean() ->
                return LayoutReflection.trySetJavaValue(host, keyString, tValue.toboolean())
            tValue.isnumber() -> {
                val d = tValue.todouble()
                val asInt = d.toInt()
                if (asInt.toDouble() == d &&
                    LayoutReflection.trySetJavaValue(host, keyString, asInt)
                ) {
                    return true
                }
                return LayoutReflection.trySetJavaValue(host, keyString, d.toFloat())
            }
            tValue.isstring() -> {
                // 常见 View 布尔字符串（canSet 已通过）
                when (keyString) {
                    "enabled" -> {
                        host.isEnabled = values.toBoolean(rawValue)
                        return true
                    }
                    "selected" -> {
                        host.isSelected = values.toBoolean(rawValue)
                        return true
                    }
                    "clickable" -> {
                        host.isClickable = values.toBoolean(rawValue)
                        return true
                    }
                    "focusable" -> {
                        host.isFocusable = values.toBoolean(rawValue)
                        return true
                    }
                }
                val javaVal = values.toValue(tValue.asString(), keyString) ?: return false
                return LayoutReflection.trySetJavaValue(host, keyString, javaVal)
            }
            tValue.isuserdata(ColorStateList::class.java) -> {
                val csl = tValue.touserdata(ColorStateList::class.java) as ColorStateList
                return LayoutReflection.trySetJavaValue(host, keyString, csl)
            }
            tValue.isuserdata() -> {
                val raw = tValue.touserdata() ?: return false
                return LayoutReflection.trySetJavaValue(host, keyString, raw)
            }
        }
        return false
    }
}

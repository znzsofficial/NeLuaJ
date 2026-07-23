package com.androlua.layout

import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.coordinatorlayout.widget.CoordinatorLayout
import com.androlua.LuaContext
import com.nekolaska.ktx.asString
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.behavior.HideBottomViewOnScrollBehavior
import com.google.android.material.behavior.HideViewOnScrollBehavior
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.search.SearchBar
import com.google.android.material.sidesheet.SideSheetBehavior
import com.google.android.material.transformation.FabTransformationScrimBehavior
import com.google.android.material.transformation.FabTransformationSheetBehavior
import com.nekolaska.ktx.ifNotNil
import com.nekolaska.ktx.toLuaValue
import org.luaj.LuaError
import org.luaj.LuaValue
import org.luaj.LuaValue.NIL
import java.util.concurrent.ConcurrentHashMap

/**
 * layout_* 参数、margin、padding、Coordinator behavior。
 */
internal class LayoutParamsApplier(
    private val luaContext: LuaContext,
    private val values: LayoutValueParser,
    private val ids: Map<String, Int>,
) {

    companion object {
        private val NO_LP = Any()
        private val nestedLpClassCache = ConcurrentHashMap<Class<*>, Any>()

        /**
         * 解析父 View 类给子节点用的 LayoutParams **类**。
         * 不可用 JavaClass["LayoutParams"]：叶子 View 会误调 getLayoutParams()。
         */
        fun resolveNestedLayoutParamsClass(parentClass: Class<*>): Class<*>? {
            if (!ViewGroup::class.java.isAssignableFrom(parentClass)) return null
            val hit = nestedLpClassCache[parentClass]
            if (hit === NO_LP) return null
            if (hit is Class<*>) return hit

            var c: Class<*>? = parentClass
            while (c != null && ViewGroup::class.java.isAssignableFrom(c)) {
                val nested = c.declaredClasses.firstOrNull { nested ->
                    nested.simpleName == "LayoutParams" &&
                        ViewGroup.LayoutParams::class.java.isAssignableFrom(nested)
                } ?: c.classes.firstOrNull { nested ->
                    nested.simpleName == "LayoutParams" &&
                        ViewGroup.LayoutParams::class.java.isAssignableFrom(nested)
                }
                if (nested != null) {
                    nestedLpClassCache[parentClass] = nested
                    return nested
                }
                c = c.superclass
            }
            nestedLpClassCache[parentClass] = NO_LP
            return null
        }

        fun resolveNestedLayoutParamsLua(parentClassValue: LuaValue): LuaValue {
            val clazz = try {
                if (parentClassValue.isuserdata(Class::class.java)) {
                    parentClassValue.touserdata(Class::class.java) as Class<*>
                } else null
            } catch (_: Exception) {
                null
            } ?: return NIL
            return resolveNestedLayoutParamsClass(clazz)?.toLuaValue() ?: NIL
        }
    }

    fun applyLayoutParam(keyString: String, tValue: LuaValue, params: LuaValue) {
        if (keyString == "layout_alignWithParentIfMissing") {
            params["alignWithParent"] = values.toBoolean(tValue).toLuaValue()
            return
        }

        val rule = LayoutEnums.relativeRules[keyString]
        if (rule != null) {
            applyRelativeRule(keyString, rule, tValue, params)
            return
        }

        val javaLp = try {
            params.touserdata()
        } catch (_: Exception) {
            null
        }

        when (keyString) {
            "layout_width" -> {
                val w = values.toLayoutSize(tValue)
                if (javaLp is ViewGroup.LayoutParams) javaLp.width = w
                else params["width"] = w
            }
            "layout_height" -> {
                val h = values.toLayoutSize(tValue)
                if (javaLp is ViewGroup.LayoutParams) javaLp.height = h
                else params["height"] = h
            }
            "layout_weight" -> {
                val w = when {
                    tValue.isnumber() -> tValue.todouble().toFloat()
                    tValue.isstring() -> tValue.asString().toFloatOrNull()
                        ?: throw LuaError("layout_weight 无法解析: ${tValue.asString()}")
                    else -> tValue.todouble().toFloat()
                }
                // AppBarLayout.LayoutParams 继承 LinearLayout.LayoutParams，一并覆盖
                if (javaLp is LinearLayout.LayoutParams) {
                    javaLp.weight = w
                    return
                }
                params["weight"] = w.toDouble()
            }
            "layout_gravity" -> {
                val g = values.toIntValue(tValue, "layout_gravity")
                when (javaLp) {
                    is LinearLayout.LayoutParams -> {
                        javaLp.gravity = g
                        return
                    }
                    is FrameLayout.LayoutParams -> {
                        javaLp.gravity = g
                        return
                    }
                    is CoordinatorLayout.LayoutParams -> {
                        javaLp.gravity = g
                        return
                    }
                }
                params["gravity"] = g
            }
            "layout_margin", "layout_marginLeft", "layout_marginTop",
            "layout_marginRight", "layout_marginBottom",
            "layout_marginStart", "layout_marginEnd",
            "layout_marginHorizontal", "layout_marginVertical" -> {
                /* deferred to applyMargins */
            }
            "layout_behavior" -> applyBehavior(tValue, params)
            "layout_anchor" -> {
                val anchorName = tValue.asString().trim()
                val anchorId = ids[anchorName]
                if (anchorId != null) {
                    val setter = params["setAnchorId"]
                    if (setter.isnil()) {
                        luaContext.sendMsg(
                            "loadlayout: layout_anchor 需要 CoordinatorLayout.LayoutParams，当前 LayoutParams 无 setAnchorId"
                        )
                    } else {
                        setter.jcall(anchorId)
                    }
                } else {
                    luaContext.sendMsg(
                        "loadlayout: layout_anchor 引用了未定义的 id '$anchorName'（须先于本控件定义）"
                    )
                }
            }
            "layout_collapseParallaxMultiplier" -> {
                val f = when {
                    tValue.isnumber() -> tValue.todouble().toFloat()
                    tValue.isstring() -> tValue.asString().toFloatOrNull()
                        ?: throw LuaError("layout_collapseParallaxMultiplier 无效")
                    else -> tValue.todouble().toFloat()
                }
                params["setParallaxMultiplier"].jcall(f)
            }
            "layout_collapseMode" ->
                params["setCollapseMode"].jcall(
                    values.toIntValue(tValue, "layout_collapseMode")
                )
            "layout_scrollFlags" ->
                params["setScrollFlags"].jcall(
                    values.toIntValue(tValue, "layout_scrollFlags")
                )
            else -> {
                if (!keyString.startsWith("layout_") || keyString.length <= 7) {
                    throw LuaError("无法识别的布局参数: $keyString")
                }
                val lpKey = layoutParamFieldName(keyString)
                val lpClass = try {
                    params.touserdata()?.javaClass
                        ?: ViewGroup.LayoutParams::class.java
                } catch (_: Exception) {
                    ViewGroup.LayoutParams::class.java
                }
                if (lpKey !in LayoutEnums.commonLayoutParamKeys &&
                    !LayoutReflection.canSetJavaProperty(lpClass, lpKey)
                ) {
                    throw LuaError(
                        "不支持的布局参数 '$keyString'（${lpClass.simpleName} 无 field/setter '$lpKey'）"
                    )
                }
                params[lpKey] = tValue
            }
        }
    }

    /**
     * 首遍 [LuaLayout.load] 收集的 margin / padding 原始值，避免二次 layout["…"] 扫表。
     * 字段为 null 表示布局表未写该 key。
     */
    class Box {
        var marginAll: LuaValue? = null
        var marginLeft: LuaValue? = null
        var marginTop: LuaValue? = null
        var marginRight: LuaValue? = null
        var marginBottom: LuaValue? = null
        var marginStart: LuaValue? = null
        var marginEnd: LuaValue? = null
        var marginHorizontal: LuaValue? = null
        var marginVertical: LuaValue? = null
        var paddingAll: LuaValue? = null
        var paddingLeft: LuaValue? = null
        var paddingTop: LuaValue? = null
        var paddingRight: LuaValue? = null
        var paddingBottom: LuaValue? = null
        var paddingStart: LuaValue? = null
        var paddingEnd: LuaValue? = null
        var hasMargin: Boolean = false
        var hasPadding: Boolean = false

        fun accept(key: String, value: LuaValue): Boolean {
            when (key) {
                "layout_margin" -> {
                    marginAll = value; hasMargin = true
                }
                "layout_marginLeft" -> {
                    marginLeft = value; hasMargin = true
                }
                "layout_marginTop" -> {
                    marginTop = value; hasMargin = true
                }
                "layout_marginRight" -> {
                    marginRight = value; hasMargin = true
                }
                "layout_marginBottom" -> {
                    marginBottom = value; hasMargin = true
                }
                "layout_marginStart" -> {
                    marginStart = value; hasMargin = true
                }
                "layout_marginEnd" -> {
                    marginEnd = value; hasMargin = true
                }
                "layout_marginHorizontal" -> {
                    marginHorizontal = value; hasMargin = true
                }
                "layout_marginVertical" -> {
                    marginVertical = value; hasMargin = true
                }
                "padding" -> {
                    paddingAll = value; hasPadding = true
                }
                "paddingLeft" -> {
                    paddingLeft = value; hasPadding = true
                }
                "paddingTop" -> {
                    paddingTop = value; hasPadding = true
                }
                "paddingRight" -> {
                    paddingRight = value; hasPadding = true
                }
                "paddingBottom" -> {
                    paddingBottom = value; hasPadding = true
                }
                "paddingStart" -> {
                    paddingStart = value; hasPadding = true
                }
                "paddingEnd" -> {
                    paddingEnd = value; hasPadding = true
                }
                else -> return false
            }
            return true
        }
    }

    fun applyMargins(box: Box, params: LuaValue) {
        if (!box.hasMargin) return
        fun dim(v: LuaValue?): Int? =
            if (v == null || v.isnil()) null else values.toLayoutSize(v)

        val all = dim(box.marginAll)
        val horizontal = dim(box.marginHorizontal)
        val vertical = dim(box.marginVertical)
        val left = dim(box.marginLeft) ?: horizontal ?: all
        val top = dim(box.marginTop) ?: vertical ?: all
        val right = dim(box.marginRight) ?: horizontal ?: all
        val bottom = dim(box.marginBottom) ?: vertical ?: all
        val start = dim(box.marginStart)
            ?: if (box.marginLeft == null) (horizontal ?: all) else null
        val end = dim(box.marginEnd)
            ?: if (box.marginRight == null) (horizontal ?: all) else null

        // 热路径：直接写 MarginLayoutParams 字段，避免 params["leftMargin"]= 桥
        val javaLp = try {
            params.touserdata()
        } catch (_: Exception) {
            null
        }
        if (javaLp is ViewGroup.MarginLayoutParams) {
            left?.let { javaLp.leftMargin = it }
            top?.let { javaLp.topMargin = it }
            right?.let { javaLp.rightMargin = it }
            bottom?.let { javaLp.bottomMargin = it }
            start?.let { javaLp.marginStart = it }
            end?.let { javaLp.marginEnd = it }
            return
        }

        left?.let { params["leftMargin"] = it }
        top?.let { params["topMargin"] = it }
        right?.let { params["rightMargin"] = it }
        bottom?.let { params["bottomMargin"] = it }
        start?.let { params["setMarginStart"]?.ifNotNil()?.jcall(it) }
        end?.let { params["setMarginEnd"]?.ifNotNil()?.jcall(it) }
    }

    fun applyPadding(box: Box, host: View) {
        if (!box.hasPadding) return
        fun dim(v: LuaValue?): Int? =
            if (v == null || v.isnil()) null else values.toLayoutSize(v)

        val all = dim(box.paddingAll)
        val left = dim(box.paddingLeft)
        val top = dim(box.paddingTop)
        val right = dim(box.paddingRight)
        val bottom = dim(box.paddingBottom)
        val start = dim(box.paddingStart)
        val end = dim(box.paddingEnd)

        if (all == null && left == null && top == null && right == null &&
            bottom == null && start == null && end == null
        ) {
            return
        }

        if (start != null || end != null) {
            host.setPaddingRelative(
                start ?: left ?: all ?: host.paddingStart,
                top ?: all ?: host.paddingTop,
                end ?: right ?: all ?: host.paddingEnd,
                bottom ?: all ?: host.paddingBottom
            )
        } else {
            host.setPadding(
                left ?: all ?: host.paddingLeft,
                top ?: all ?: host.paddingTop,
                right ?: all ?: host.paddingRight,
                bottom ?: all ?: host.paddingBottom
            )
        }
    }

    /** 兼容：仍从 layout 表读（测试 / 外部调用） */
    fun applyMargins(layout: LuaValue, params: LuaValue) {
        val box = Box()
        fun take(key: String) {
            val v = layout[key]
            if (!v.isnil()) box.accept(key, v)
        }
        take("layout_margin")
        take("layout_marginLeft")
        take("layout_marginTop")
        take("layout_marginRight")
        take("layout_marginBottom")
        take("layout_marginStart")
        take("layout_marginEnd")
        take("layout_marginHorizontal")
        take("layout_marginVertical")
        applyMargins(box, params)
    }

    fun applyPadding(layout: LuaValue, host: View) {
        val box = Box()
        fun take(key: String) {
            val v = layout[key]
            if (!v.isnil()) box.accept(key, v)
        }
        take("padding")
        take("paddingLeft")
        take("paddingTop")
        take("paddingRight")
        take("paddingBottom")
        take("paddingStart")
        take("paddingEnd")
        applyPadding(box, host)
    }

    private fun layoutParamFieldName(layoutKey: String): String {
        val rest = layoutKey.substring(7)
        return LayoutEnums.layoutFieldAliases[rest] ?: rest
    }

    private fun applyRelativeRule(
        keyString: String,
        rule: Int,
        tValue: LuaValue,
        params: LuaValue
    ) {
        when {
            tValue.isboolean() && tValue.toboolean() ->
                params["addRule"].jcall(rule)
            tValue.isstring() -> {
                val s = tValue.asString()
                if (s == "true") {
                    params["addRule"].jcall(rule)
                } else {
                    val targetId = ids[s]
                    if (targetId != null) {
                        params["addRule"].jcall(rule, targetId)
                    } else {
                        luaContext.sendMsg(
                            "loadlayout: $keyString 引用了未定义的 id '$s'\n" +
                                "请确保目标视图的 id 在当前视图之前定义"
                        )
                    }
                }
            }
            tValue.isnumber() -> params["addRule"].jcall(rule, tValue.toint())
            else -> params["addRule"].jcall(rule)
        }
    }

    private fun applyBehavior(tValue: LuaValue, params: LuaValue) {
        if (tValue.isstring()) {
            val name = tValue.asString()
            val behavior = createBehaviorFromString(name)
            if (behavior != null) {
                params["setBehavior"].jcall(behavior)
            } else {
                luaContext.sendMsg(
                    "loadlayout: 未知 layout_behavior \"$name\"，将原样传递"
                )
                params["setBehavior"].jcall(tValue)
            }
        } else {
            params["setBehavior"].jcall(tValue)
        }
    }

    @Suppress("DEPRECATION")
    private fun createBehaviorFromString(behaviorString: String): Any? = when (behaviorString) {
        "@string/appbar_scrolling_view_behavior" -> AppBarLayout.ScrollingViewBehavior()
        "@string/bottom_sheet_behavior" -> BottomSheetBehavior()
        "@string/side_sheet_behavior" -> SideSheetBehavior()
        "@string/hide_bottom_view_on_scroll_behavior" -> HideBottomViewOnScrollBehavior()
        "@string/hide_view_on_scroll_behavior" -> HideViewOnScrollBehavior()
        "@string/searchbar_scrolling_view_behavior" -> SearchBar.ScrollingViewBehavior()
        "@string/fab_transformation_scrim_behavior" -> FabTransformationScrimBehavior()
        "@string/fab_transformation_sheet_behavior" -> FabTransformationSheetBehavior()
        else -> null
    }
}

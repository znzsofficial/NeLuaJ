package com.androlua.layout

import android.view.View
import android.view.ViewGroup
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

/**
 * layout_* 参数、margin、padding、Coordinator behavior。
 */
internal class LayoutParamsApplier(
    private val luaContext: LuaContext,
    private val values: LayoutValueParser,
    private val ids: Map<String, Int>,
) {

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

        when (keyString) {
            "layout_width" -> params["width"] = values.toLayoutSize(tValue)
            "layout_height" -> params["height"] = values.toLayoutSize(tValue)
            "layout_weight" -> {
                val w = when {
                    tValue.isnumber() -> tValue.todouble()
                    tValue.isstring() -> tValue.asString().toDoubleOrNull()
                        ?: throw LuaError("layout_weight 无法解析: ${tValue.asString()}")
                    else -> tValue.todouble()
                }
                params["weight"] = w
            }
            "layout_gravity" ->
                params["gravity"] = values.toIntValue(tValue, "layout_gravity")
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

    fun applyMargins(layout: LuaValue, params: LuaValue) {
        fun raw(key: String): LuaValue {
            val v = layout[key]
            return if (v.isnil()) NIL else v
        }
        fun dim(key: String): Int? {
            val v = raw(key)
            return if (v.isnil()) null else values.toLayoutSize(v)
        }

        val all = dim("layout_margin")
        val horizontal = dim("layout_marginHorizontal")
        val vertical = dim("layout_marginVertical")
        val left = dim("layout_marginLeft") ?: horizontal ?: all
        val top = dim("layout_marginTop") ?: vertical ?: all
        val right = dim("layout_marginRight") ?: horizontal ?: all
        val bottom = dim("layout_marginBottom") ?: vertical ?: all

        left?.let { params["leftMargin"] = it }
        top?.let { params["topMargin"] = it }
        right?.let { params["rightMargin"] = it }
        bottom?.let { params["bottomMargin"] = it }

        val start = dim("layout_marginStart")
            ?: if (raw("layout_marginLeft").isnil()) (horizontal ?: all) else null
        val end = dim("layout_marginEnd")
            ?: if (raw("layout_marginRight").isnil()) (horizontal ?: all) else null
        start?.let { params["setMarginStart"]?.ifNotNil()?.jcall(it) }
        end?.let { params["setMarginEnd"]?.ifNotNil()?.jcall(it) }
    }

    fun applyPadding(layout: LuaValue, host: View) {
        fun dim(key: String): Int? {
            val v = layout[key]
            return if (v.isnil()) null else values.toLayoutSize(v)
        }

        val all = dim("padding")
        val left = dim("paddingLeft")
        val top = dim("paddingTop")
        val right = dim("paddingRight")
        val bottom = dim("paddingBottom")
        val start = dim("paddingStart")
        val end = dim("paddingEnd")

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

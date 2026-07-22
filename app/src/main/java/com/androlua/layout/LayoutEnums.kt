package com.androlua.layout

import android.view.ViewGroup
import com.nekolaska.ktx.toLuaValue
import org.luaj.LuaValue

/**
 * loadlayout 枚举 / 尺寸关键字 / RelativeLayout rules / 尺寸单位。
 * 按属性分表，避免同名键互相覆盖（如 inherit、none）。
 */
internal object LayoutEnums {

    val wrapContent: LuaValue = ViewGroup.LayoutParams.WRAP_CONTENT.toLuaValue()

    /** 尺寸关键字：跨属性无歧义 */
    val sizeTokens: Map<String, Int> = mapOf(
        "wrap_content" to -2,
        "fill_parent" to -1,
        "match_parent" to -1,
        "wrap" to -2,
        "fill" to -1,
        "match" to -1,
    )

    /** TypedValue 单位后缀 */
    val dimensionUnits: Map<String, Int> = mapOf(
        "px" to 0, "dp" to 1, "sp" to 2, "pt" to 3, "in" to 4, "mm" to 5,
    )

    val scaleType: Map<String, Int> = mapOf(
        "matrix" to 0,
        "fitCenter" to 1,
        "fitEnd" to 2,
        "fitStart" to 3,
        "fitXY" to 4,
        "center" to 5,
        "centerCrop" to 6,
        "centerInside" to 7,
    )

    /** RelativeLayout addRule 动词 → rule id */
    val relativeRules: Map<String, Int> = mapOf(
        "layout_above" to 2,
        "layout_alignBaseline" to 4,
        "layout_alignBottom" to 8,
        "layout_alignEnd" to 19,
        "layout_alignLeft" to 5,
        "layout_alignParentBottom" to 12,
        "layout_alignParentEnd" to 21,
        "layout_alignParentLeft" to 9,
        "layout_alignParentRight" to 11,
        "layout_alignParentStart" to 20,
        "layout_alignParentTop" to 10,
        "layout_alignRight" to 7,
        "layout_alignStart" to 18,
        "layout_alignTop" to 6,
        "layout_below" to 3,
        "layout_centerHorizontal" to 14,
        "layout_centerInParent" to 13,
        "layout_centerVertical" to 15,
        "layout_toEndOf" to 17,
        "layout_toLeftOf" to 0,
        "layout_toRightOf" to 1,
        "layout_toStartOf" to 16,
    )

    /**
     * layout_ 后缀 → MarginLayoutParams 真实字段名。
     * Android 是 leftMargin，不是 marginLeft。
     */
    val layoutFieldAliases: Map<String, String> = mapOf(
        "marginLeft" to "leftMargin",
        "marginTop" to "topMargin",
        "marginRight" to "rightMargin",
        "marginBottom" to "bottomMargin",
        "marginStart" to "marginStart",
        "marginEnd" to "marginEnd",
    )

    /** 常见 LayoutParams 字段：可跳过 canSet 扫描 */
    val commonLayoutParamKeys: Set<String> = setOf(
        "width", "height", "weight", "gravity",
        "leftMargin", "topMargin", "rightMargin", "bottomMargin",
        "marginStart", "marginEnd",
        "column", "row", "columnSpan", "rowSpan",
        "order", "layoutDirection",
    )

    private val drawingCacheQuality = mapOf("auto" to 0, "low" to 1, "high" to 2)
    private val importantForAccessibility = mapOf("auto" to 0, "yes" to 1, "no" to 2)
    private val layerType = mapOf("none" to 0, "software" to 1, "hardware" to 2)
    private val layoutDirection = mapOf("ltr" to 0, "rtl" to 1, "inherit" to 2, "locale" to 3)
    private val scrollbarStyle = mapOf(
        "insideOverlay" to 0x0,
        "insideInset" to 0x01000000,
        "outsideOverlay" to 0x02000000,
        "outsideInset" to 0x03000000,
    )
    val visibility: Map<String, Int> = mapOf(
        "visible" to 0, "invisible" to 4, "gone" to 8,
    )
    private val autoLink = mapOf(
        "none" to 0x00, "web" to 0x01, "email" to 0x02,
        "phone" to 0x04, "phon" to 0x04, "map" to 0x08, "all" to 0x0f,
    )
    private val orientation = mapOf("vertical" to 1, "horizontal" to 0)

    val gravity: Map<String, Int> = mapOf(
        "axis_clip" to 8,
        "axis_pull_after" to 4,
        "axis_pull_before" to 2,
        "axis_specified" to 1,
        "axis_x_shift" to 0,
        "axis_y_shift" to 4,
        "bottom" to 80,
        "center" to 17,
        "center_horizontal" to 1,
        "center_vertical" to 16,
        "clip_horizontal" to 8,
        "clip_vertical" to 128,
        "display_clip_horizontal" to 16777216,
        "display_clip_vertical" to 268435456,
        "fill" to 119,
        "fill_horizontal" to 7,
        "fill_vertical" to 112,
        "horizontal_gravity_mask" to 7,
        "left" to 3,
        "no_gravity" to 0,
        "relative_horizontal_gravity_mask" to 8388615,
        "relative_layout_direction" to 8388608,
        "right" to 5,
        "start" to 8388611,
        "top" to 48,
        "vertical_gravity_mask" to 112,
        "end" to 8388613,
    )

    private val textAlignment = mapOf(
        "inherit" to 0, "gravity" to 1, "textStart" to 2, "textEnd" to 3,
        "textCenter" to 4, "viewStart" to 5, "viewEnd" to 6,
    )

    private val inputType = mapOf(
        "none" to 0x00000000,
        "text" to 0x00000001,
        "textCapCharacters" to 0x00001001,
        "textCapWords" to 0x00002001,
        "textCapSentences" to 0x00004001,
        "textAutoCorrect" to 0x00008001,
        "textAutoComplete" to 0x00010001,
        "textMultiLine" to 0x00020001,
        "textImeMultiLine" to 0x00040001,
        "textNoSuggestions" to 0x00080001,
        "textUri" to 0x00000011,
        "textEmailAddress" to 0x00000021,
        "textEmailSubject" to 0x00000031,
        "textShortMessage" to 0x00000041,
        "textLongMessage" to 0x00000051,
        "textPersonName" to 0x00000061,
        "textPostalAddress" to 0x00000071,
        "textPassword" to 0x00000081,
        "textVisiblePassword" to 0x00000091,
        "textWebEditText" to 0x000000a1,
        "textFilter" to 0x000000b1,
        "textPhonetic" to 0x000000c1,
        "textWebEmailAddress" to 0x000000d1,
        "textWebPassword" to 0x000000e1,
        "number" to 0x00000002,
        "numberSigned" to 0x00001002,
        "numberDecimal" to 0x00002002,
        "numberPassword" to 0x00000012,
        "phone" to 0x00000003,
        "datetime" to 0x00000004,
        "date" to 0x00000014,
        "time" to 0x00000024,
    )

    private val imeOptions = mapOf(
        "normal" to 0x00000000,
        "actionUnspecified" to 0x00000000,
        "actionNone" to 0x00000001,
        "actionGo" to 0x00000002,
        "actionSearch" to 0x00000003,
        "actionSend" to 0x00000004,
        "actionNext" to 0x00000005,
        "actionDone" to 0x00000006,
        "actionPrevious" to 0x00000007,
        "flagNoFullscreen" to 0x2000000,
        "flagNavigatePrevious" to 0x4000000,
        "flagNavigateNext" to 0x8000000,
        "flagNoExtractUi" to 0x10000000,
        "flagNoAccessoryAction" to 0x20000000,
        "flagNoEnterAction" to 0x40000000,
        "flagForceAscii" to -0x80000000,
    )

    private val scrollFlags = mapOf(
        "noScroll" to 0,
        "scroll" to 1,
        "exitUntilCollapsed" to 2,
        "enterAlways" to 4,
        "enterAlwaysCollapsed" to 8,
        "snap" to 16,
        "snapMargins" to 32,
    )

    private val collapseMode = mapOf("pin" to 1, "parallax" to 2)

    fun enumMapForAttr(attr: String): Map<String, Int>? = when (attr) {
        "gravity", "layout_gravity" -> gravity
        "inputType" -> inputType
        "imeOptions" -> imeOptions
        "visibility" -> visibility
        "orientation" -> orientation
        "layoutDirection" -> layoutDirection
        "textAlignment" -> textAlignment
        "layerType" -> layerType
        "scrollbarStyle" -> scrollbarStyle
        "autoLink" -> autoLink
        "drawingCacheQuality" -> drawingCacheQuality
        "importantForAccessibility" -> importantForAccessibility
        "layout_scrollFlags", "scrollFlags" -> scrollFlags
        "layout_collapseMode", "collapseMode" -> collapseMode
        else -> null
    }
}

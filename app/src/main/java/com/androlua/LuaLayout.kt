package com.androlua

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ImageView.ScaleType
import androidx.appcompat.view.ContextThemeWrapper
import androidx.core.graphics.toColorInt
import coil3.ImageLoader
import coil3.asDrawable
import coil3.imageLoader
import coil3.request.ImageRequest
import com.androlua.adapter.ArrayListAdapter
import com.androlua.adapter.LuaAdapter
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.behavior.HideBottomViewOnScrollBehavior
import com.google.android.material.behavior.HideViewOnScrollBehavior
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.search.SearchBar
import com.google.android.material.sidesheet.SideSheetBehavior
import com.google.android.material.transformation.FabTransformationScrimBehavior
import com.google.android.material.transformation.FabTransformationSheetBehavior
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.ifNotNil
import com.nekolaska.ktx.isNotNil
import com.nekolaska.ktx.require
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import com.nekolaska.ktx.toVarargs
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
 * Created by nirenr on 2019/11/18.
 */
class LuaLayout(private val initialContext: Context) {
    private val dm: DisplayMetrics = initialContext.resources.displayMetrics
    private val views = HashMap<String, LuaValue>()
    private val luaValueContext: LuaValue = initialContext.toLuaInstance()
    private val luaContext = luaValueContext.touserdata(LuaContext::class.java)
    private val imageLoader: ImageLoader = initialContext.imageLoader
    private val scaleTypeValues: Array<ScaleType> = ScaleType.entries.toTypedArray()

    val id: HashMap<*, *>
        get() = ids

    val view: HashMap<*, *>
        get() = views

    fun type(): Int {
        return LuaValue.TUSERDATA
    }

    fun typename(): String {
        return "LuaLayout"
    }

    fun get(key: LuaValue): LuaValue? {
        return get(key.asString())
    }

    fun get(key: String): LuaValue? {
        return getView(key)
    }

    private fun getView(id: String): LuaValue? {
        return views[id]
    }

    private fun toValue(str: String): Any? {
        if (str == "nil") return 0

        // 多个 flags，用 | 分隔
        if (str.indexOf('|') >= 0) {
            var ret = 0
            for (s in str.split(PIPE_REGEX)) {
                toint[s]?.let { ret = ret or it }
            }
            return ret
        }

        toint[str]?.let { return it }

        // 颜色
        if (str.startsWith("#")) {
            return runCatching { str.toColorInt() }.getOrElse {
                str.substring(1).toInt(16).let {
                    if (str.length < 6) it or -0x1000000 else it
                }
            }
        }

        val len = str.length

        // 百分比
        if (str.endsWith("%")) {
            val f = str.dropLast(1).toFloatOrNull()
            return f?.times(luaContext.width)?.div(100)
        }

        if (len >= 3 && str[len - 2] == '%') {
            val f = str.dropLast(2).toFloatOrNull() ?: return str
            return when (str.last()) {
                'w' -> f * luaContext.width / 100
                'h' -> f * luaContext.height / 100
                else -> str
            }
        }

        // dp/sp/px/in/pt/mm
        if (len >= 3) {
            val unit = str.takeLast(2)
            types[unit]?.let { type ->
                str.dropLast(2).toFloatOrNull()?.let { value ->
                    return TypedValue.applyDimension(type, value, dm)
                }
            }
        }

        // Long or Double fallback
        str.toLongOrNull()?.let { return it }
        str.toDoubleOrNull()?.let { return it }

        return str
    }

    @Suppress("DEPRECATION")
    private fun createBehaviorFromString(behaviorString: String): Any? {
        return when (behaviorString) {
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

    private fun processLuaPages(viewsTable: LuaTable, env: LuaTable): List<View> {
        val viewList = mutableListOf<View>()
        // Lua table的长度从1开始
        for (i in 1..viewsTable.length()) {
            val v = viewsTable[i]
            val view = when {
                // userdata: 直接转换
                v.isuserdata() -> v.toView()

                // table: 加载并转换
                v.istable() -> load(v.checktable(), env).toView()

                // string: 作为文件路径require，然后加载并转换
                v.isstring() -> load(luaContext.luaState.require(v), env).toView()
                else -> throw LuaError(
                    "Unsupported type for Lua pages: ${v.typename()}. Expected userdata, table, or string."
                )
            }
            viewList.add(view)
        }
        return viewList
    }

    fun parseColor(colorString: String): Int {
        if (colorString[0] == '#') {
            // Use a long to avoid rollovers on #ffXXXXXX
            var color = colorString.substring(1).toLong(16)
            if (colorString.length <= 7) {
                // Set the alpha value
                color = color or 0x00000000ff000000L
            }
            return color.toInt()
        }
        return 0
    }

    @JvmOverloads
    fun load(
        layout: LuaValue, env: LuaTable = LuaTable(), params: LuaValue =
            ViewGroup.LayoutParams::class.java.toLuaValue()
    ): LuaValue {
        var params = params
        val viewClass = layout[1]
        if (viewClass.isnil()) throw LuaError(
            "loadlayout error: First value Must be a Class, checked import package.\nat ${layout.checktable().dump()}"
        )
        val view = layout["style"].run {
            if (isNotNil()) viewClass.call(
                ContextThemeWrapper(initialContext, toint()).toLuaInstance(),
                NIL,
                this
            ) else viewClass.call(luaValueContext)
        }
        params = params.call(Wrap, Wrap)
        try {
            var key = NIL
            var next: Varargs
            while (!layout.next(key).also { next = it }.firstArg().isnil()) {
                try {
                    key = next.firstArg()
                    if (key.isint()) {
                        if (key.toint() > 1) {
                            var v = next.secondArg()
                            if (v.isstring()) v =
                                luaContext.luaState.require(v)
                            if (viewClass.isuserdata() && AdapterView::class.java.isAssignableFrom(
                                    viewClass.touserdata(
                                        Class::class.java
                                    )
                                )
                            ) {
                                view.jset(
                                    "adapter",
                                    LuaAdapter(
                                        luaContext,
                                        v.checktable()
                                    )
                                )
                            } else {
                                v = load(v, env, viewClass["LayoutParams"])
                                view["addView"].call(v)
                            }
                        }
                    } else if (key.isstring()) {
                        var keyString = key.asString()
                        var tValue = next.secondArg()

                        when (keyString) {
                            "padding" -> continue
                            "id" -> {
                                view["id"] = idx
                                views[tValue.asString()] = view
                                ids[tValue.asString()] = idx
                                env[tValue] = view
                                idx++
                                continue
                            }

                            "text" -> {
                                view["text"] = tValue.tostring()
                                continue
                            }

                            "textSize" -> {
                                view["setTextSize"].jcall(0, toValue(tValue.asString()))
                                continue
                            }

                            "textStyle" -> {
                                when (tValue.asString()) {
                                    "bold" ->
                                        view["setTypeface"].jcall(
                                            Typeface.defaultFromStyle(
                                                Typeface.BOLD
                                            )
                                        )

                                    "normal" ->
                                        view["setTypeface"]
                                            .jcall(Typeface.defaultFromStyle(Typeface.NORMAL))

                                    "italic" ->
                                        view["setTypeface"].jcall(
                                            Typeface.defaultFromStyle(Typeface.ITALIC)
                                        )

                                    "italic|bold", "bold|italic" ->
                                        view["setTypeface"].jcall(
                                            Typeface.defaultFromStyle(Typeface.BOLD_ITALIC)
                                        )

                                    else -> throw LuaError(
                                        "Unsupported textStyle: ${tValue.asString()}"
                                    )
                                }
                                continue
                            }

                            "scaleType" -> {
                                view["setScaleType"]
                                    .jcall(scaleTypeValues[scaleType[tValue.asString()]!!])
                                continue
                            }

                            "ellipsize" -> {
                                view["setEllipsize"]
                                    .jcall(
                                        TextUtils.TruncateAt.valueOf(
                                            tValue.asString().uppercase(
                                                Locale.getDefault()
                                            )
                                        )
                                    )
                                continue
                            }

                            "hint" -> {
                                view["hint"] = tValue.tostring()
                                continue
                            }

                            "items" -> {
                                val adapter = view["adapter"]
                                if (adapter.isNotNil()) {
                                    adapter["addAll"].call(tValue)
                                } else {
                                    view["setAdapter"]
                                        .jcall(
                                            ArrayListAdapter(
                                                initialContext,
                                                android.R.layout.simple_list_item_1,
                                                CoerceLuaToJava.arrayCoerce(
                                                    tValue,
                                                    String::class.java
                                                ) as Array<*>
                                            )
                                        )
                                }
                                continue
                            }

                            "minHeight" -> {
                                view["MinimumHeight"] = tValue.tostring()
                                continue
                            }

                            "minWidth" -> {
                                view["MinimumWidth"] = tValue.tostring()
                                continue
                            }

                            "pages" -> {
                                val viewsTable = tValue.checktable()
                                val viewList = processLuaPages(viewsTable, env)
                                view["setAdapter"].jcall(LuaPagerAdapter(viewList))
                                continue
                            }

                            "pagesWithTitle" -> {
                                val pagesWithTitleTable = tValue.checktable()
                                val viewsTable = pagesWithTitleTable[1].checktable()
                                val titlesTable = pagesWithTitleTable[2].checktable()

                                // 复用页面处理逻辑
                                val viewList = processLuaPages(viewsTable, env)

                                // 处理标题列表
                                val titleList = mutableListOf<String>()
                                for (i in 1..titlesTable.length()) {
                                    titleList.add(titlesTable[i].asString())
                                }

                                view["setAdapter"].jcall(LuaPagerAdapter(viewList, titleList))
                                continue
                            }

                            "src" -> {
                                if (tValue.isuserdata(Bitmap::class.java)) {
                                    view.jset(
                                        "ImageBitmap", tValue.touserdata(
                                            Bitmap::class.java
                                        )
                                    )
                                } else if (tValue.isuserdata(Drawable::class.java)) {
                                    view.jset(
                                        "ImageDrawable", tValue.touserdata(
                                            Drawable::class.java
                                        )
                                    )
                                } else {
                                    imageLoader.enqueue(
                                        ImageRequest.Builder(initialContext)
                                            .data(tValue.asString()).target {
                                                view.jset(
                                                    "ImageDrawable",
                                                    it.asDrawable(initialContext.resources)
                                                )
                                            }.build()
                                    )
                                }
                                continue
                            }

                            "background" -> {
                                if (tValue.isuserdata()) {
                                    view.jset(
                                        "background", tValue.touserdata(
                                            Drawable::class.java
                                        )
                                    )
                                } else if (tValue.isnumber()) {
                                    view.jset("backgroundColor", tValue.toint())
                                } else if (tValue.isstring()) {
                                    val str = tValue.asString()
                                    if (str.startsWith("#")) {
                                        view.jset("backgroundColor", parseColor(str))
                                    } else {
                                        view.jset(
                                            "background",
                                            LuaBitmapDrawable(
                                                luaContext,
                                                str
                                            )
                                        )
                                    }
                                }
                                continue
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
                            }
                        }
                        if (tValue.type() == LuaValue.TSTRING) {
                            tValue = toValue(tValue.asString()).toLuaValue()
                        }
                        if (keyString.startsWith("layout")) {
                            if (rules.containsKey(keyString)) {
                                if (tValue.isboolean() && tValue.toboolean()) params["addRule"].jcall(
                                    rules[keyString]
                                )
                                else if (tValue.asString() == "true") params["addRule"].jcall(
                                    rules[keyString]
                                )
                                else params["addRule"].jcall(
                                    rules[keyString],
                                    ids[tValue.asString()]
                                )
                            } else if (keyString == "layout_behavior") {
                                params["setBehavior"].jcall(
                                    createBehaviorFromString(tValue.asString()) ?: tValue
                                )
                            } else if (keyString == "layout_anchor") {
                                params["setAnchorId"].jcall(ids[tValue.asString()])
                            } else if (keyString == "layout_collapseParallaxMultiplier") {
                                params["setParallaxMultiplier"].jcall(tValue)
                            } else if (keyString == "layout_marginEnd") {
                                params["setMarginEnd"].jcall(tValue)
                            } else if (keyString == "layout_marginStart") {
                                params["setMarginStart"].jcall(tValue)
                            } else if (keyString == "layout_collapseMode") {
                                params["setCollapseMode"].jcall(tValue)
                            } else if (keyString == "layout_scrollFlags") {
                                params["setScrollFlags"].jcall(tValue)
                            } else {
                                keyString = keyString.substring(7)
                                params[keyString] = tValue
                            }
                        } else {
                            view[key] = tValue
                            //view.jset(key.asString(), tValue)
                        }
                    }
                } catch (e: Exception) {
                    luaContext
                        .sendError(
                            "loadlayout " + view + ": " + next.firstArg() + "=" + next.secondArg(),
                            e
                        )
                    e.printStackTrace()
                }
            }

            runCatching {
                val mss = arrayOfNulls<LuaValue>(4)
                var sp = false
                for (i in ms.indices) {
                    var pt = layout[ms[i]]
                    if (pt.isnil())
                        pt = layout["layout_margin"]
                    if (pt.isnil()) {
                        pt = view[pt]
                    } else {
                        sp = true
                    }
                    mss[i] = toValue(pt.asString()).toLuaValue()
                }
                if (sp) params["setMargins"]?.ifNotNil()?.invoke(mss.toVarargs())
            }.onFailure { it.printStackTrace() }

            view["LayoutParams"] = params
            runCatching {
                val pds = arrayOfNulls<LuaValue>(4)
                var sp = false
                for (i in ps.indices) {
                    var pt = layout[ps[i]]
                    if (pt.isnil())
                        pt = layout["padding"]
                    if (pt.isnil()) {
                        pt = view[pt]
                    } else {
                        sp = true
                    }
                    pds[i] = toValue(pt.asString()).toLuaValue()
                }
                if (sp) view["setPadding"].invoke(pds.toVarargs())
            }.onFailure {
                luaContext
                    .sendError("loadlayout " + layout.checktable().dump(), it as Exception)
                it.printStackTrace()
            }
        } catch (e: Exception) {
            luaContext
                .sendError("loadlayout " + layout.checktable().dump(), e)
            e.printStackTrace()
        }
        return view
    }

    companion object {
        private val toint = HashMap<String, Int>()

        init {
            // android:drawingCacheQuality
            toint["auto"] = 0
            toint["low"] = 1
            toint["high"] = 2

            // android:importantForAccessibility
            // toint.put("auto", 0);
            toint["yes"] = 1
            toint["no"] = 2

            // android:layerType
            toint["none"] = 0
            toint["software"] = 1
            toint["hardware"] = 2

            // android:layoutDirection
            toint["ltr"] = 0
            toint["rtl"] = 1
            toint["inherit"] = 2
            toint["locale"] = 3

            // android:scrollbarStyle
            toint["insideOverlay"] = 0x0
            toint["insideInset"] = 0x01000000
            toint["outsideOverlay"] = 0x02000000
            toint["outsideInset"] = 0x03000000

            // android:visibility
            toint["visible"] = 0
            toint["invisible"] = 4
            toint["gone"] = 8

            toint["wrap_content"] = -2
            toint["fill_parent"] = -1
            toint["match_parent"] = -1
            toint["wrap"] = -2
            toint["fill"] = -1
            toint["match"] = -1

            // android:autoLink
            // toint.put("none", 0x00);
            toint["web"] = 0x01
            toint["email"] = 0x02
            toint["phon"] = 0x04
            toint["toint"] = 0x08
            toint["all"] = 0x0f

            // android:orientation
            toint["vertical"] = 1
            toint["horizontal"] = 0

            // android:gravity
            toint["axis_clip"] = 8
            toint["axis_pull_after"] = 4
            toint["axis_pull_before"] = 2
            toint["axis_specified"] = 1
            toint["axis_x_shift"] = 0
            toint["axis_y_shift"] = 4
            toint["bottom"] = 80
            toint["center"] = 17
            toint["center_horizontal"] = 1
            toint["center_vertical"] = 16
            toint["clip_horizontal"] = 8
            toint["clip_vertical"] = 128
            toint["display_clip_horizontal"] = 16777216
            toint["display_clip_vertical"] = 268435456
            // toint.put("fill",119);
            toint["fill_horizontal"] = 7
            toint["fill_vertical"] = 112
            toint["horizontal_gravity_mask"] = 7
            toint["left"] = 3
            toint["no_gravity"] = 0
            toint["relative_horizontal_gravity_mask"] = 8388615
            toint["relative_layout_direction"] = 8388608
            toint["right"] = 5
            toint["start"] = 8388611
            toint["top"] = 48
            toint["vertical_gravity_mask"] = 112
            toint["end"] = 8388613

            // android:textAlignment
            toint["inherit"] = 0
            toint["gravity"] = 1
            toint["textStart"] = 2
            toint["textEnd"] = 3
            toint["textCenter"] = 4
            toint["viewStart"] = 5
            toint["viewEnd"] = 6

            // android:inputType
            // toint.put("none", 0x00000000);
            toint["text"] = 0x00000001
            toint["textCapCharacters"] = 0x00001001
            toint["textCapWords"] = 0x00002001
            toint["textCapSentences"] = 0x00004001
            toint["textAutoCorrect"] = 0x00008001
            toint["textAutoComplete"] = 0x00010001
            toint["textMultiLine"] = 0x00020001
            toint["textImeMultiLine"] = 0x00040001
            toint["textNoSuggestions"] = 0x00080001
            toint["textUri"] = 0x00000011
            toint["textEmailAddress"] = 0x00000021
            toint["textEmailSubject"] = 0x00000031
            toint["textShortMessage"] = 0x00000041
            toint["textLongMessage"] = 0x00000051
            toint["textPersonName"] = 0x00000061
            toint["textPostalAddress"] = 0x00000071
            toint["textPassword"] = 0x00000081
            toint["textVisiblePassword"] = 0x00000091
            toint["textWebEditText"] = 0x000000a1
            toint["textFilter"] = 0x000000b1
            toint["textPhonetic"] = 0x000000c1
            toint["textWebEmailAddress"] = 0x000000d1
            toint["textWebPassword"] = 0x000000e1
            toint["number"] = 0x00000002
            toint["numberSigned"] = 0x00001002
            toint["numberDecimal"] = 0x00002002
            toint["numberPassword"] = 0x00000012
            toint["phone"] = 0x00000003
            toint["datetime"] = 0x00000004
            toint["date"] = 0x00000014
            toint["time"] = 0x00000024

            // android:imeOptions
            toint["normal"] = 0x00000000
            toint["actionUnspecified"] = 0x00000000
            toint["actionNone"] = 0x00000001
            toint["actionGo"] = 0x00000002
            toint["actionSearch"] = 0x00000003
            toint["actionSend"] = 0x00000004
            toint["actionNext"] = 0x00000005
            toint["actionDone"] = 0x00000006
            toint["actionPrevious"] = 0x00000007
            toint["flagNoFullscreen"] = 0x2000000
            toint["flagNavigatePrevious"] = 0x4000000
            toint["flagNavigateNext"] = 0x8000000
            toint["flagNoExtractUi"] = 0x10000000
            toint["flagNoAccessoryAction"] = 0x20000000
            toint["flagNoEnterAction"] = 0x40000000
            toint["flagForceAscii"] = -0x80000000

            // layout_scrollFlags
            toint["noScroll"] = 0
            toint["scroll"] = 1
            toint["exitUntilCollapsed"] = 2
            toint["enterAlways"] = 4
            toint["enterAlwaysCollapsed"] = 8
            toint["snap"] = 16
            toint["snapMargins"] = 32

            // layout_collapseMode
            toint["pin"] = 1
            toint["parallax"] = 2
        }

        private val scaleType = HashMap<String, Int>()

        init {
            scaleType["matrix"] = 0
            scaleType["fitCenter"] = 1
            scaleType["fitEnd"] = 2
            scaleType["fitStart"] = 3
            scaleType["fitXY"] = 4
            scaleType["center"] = 5
            scaleType["centerCrop"] = 6
            scaleType["centerInside"] = 7
        }

        private val rules = HashMap<String, Int>()

        init {
            rules["layout_above"] = 2
            rules["layout_alignBaseline"] = 4
            rules["layout_alignBottom"] = 8
            rules["layout_alignEnd"] = 19
            rules["layout_alignLeft"] = 5
            rules["layout_alignParentBottom"] = 12
            rules["layout_alignParentEnd"] = 21
            rules["layout_alignParentLeft"] = 9
            rules["layout_alignParentRight"] = 11
            rules["layout_alignParentStart"] = 20
            rules["layout_alignParentTop"] = 10
            rules["layout_alignRight"] = 7
            rules["layout_alignStart"] = 18
            rules["layout_alignTop"] = 6
            rules["layout_alignWithParentIfMissing"] = 0
            rules["layout_below"] = 3
            rules["layout_centerHorizontal"] = 14
            rules["layout_centerInParent"] = 13
            rules["layout_centerVertical"] = 15
            rules["layout_toEndOf"] = 17
            rules["layout_toLeftOf"] = 0
            rules["layout_toRightOf"] = 1
            rules["layout_toStartOf"] = 16
        }

        private val types = HashMap<String, Int>()

        init {
            types["px"] = 0
            types["dp"] = 1
            types["sp"] = 2
            types["pt"] = 3
            types["in"] = 4
            types["mm"] = 5
        }

        private val ids = HashMap<String, Int>()
        private var idx = 0x7f000000

        private val ps = arrayOf("paddingLeft", "paddingTop", "paddingRight", "paddingBottom")
        private val ms = arrayOf(
            "layout_marginLeft", "layout_marginTop", "layout_marginRight", "layout_marginBottom"
        )
        private val Wrap: LuaValue = ViewGroup.LayoutParams.WRAP_CONTENT.toLuaValue()

        private val PIPE_REGEX = Regex("\\|")
    }
}

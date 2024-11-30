package com.androlua

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
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
import coil3.ImageLoader
import coil3.asDrawable
import coil3.imageLoader
import coil3.request.ImageRequest
import com.androlua.adapter.ArrayListAdapter
import com.androlua.adapter.LuaAdapter
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.behavior.HideBottomViewOnScrollBehavior
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.sidesheet.SideSheetBehavior
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

@Suppress("NOTHING_TO_INLINE")
private inline fun LuaValue.toView(): View = this.touserdata(View::class.java)

//inline fun <T : View> T.onClick(crossinline onClick: (v: T) -> Unit) {
//    setOnClickListener { onClick(it as T) }
//}

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

    private fun toValue(s: String): Any? {
        if (s == "nil") return 0
        val len = s.length

        if (s.contains("|")) {
            val ss = s.split("\\|".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
            var ret = 0
            for (s1 in ss) {
                if (toint.containsKey(s1)) ret = ret or toint[s1]!!
            }
            return ret
        }
        if (toint.containsKey(s)) return toint[s]

        if (len > 2) {
            if (s[0] == '#') {
                try {
                    return Color.parseColor(s)
                } catch (e: Exception) {
                    val clr = s.substring(1).toInt(16)
                    if (s.length < 6) return clr or -0x1000000
                    return clr
                }
            }
            if (s[len - 1] == '%') {
                val f = s.substring(0, len - 1).toFloat()
                return f * luaContext.width / 100
            }

            if (s[len - 2] == '%') {
                val f = s.substring(0, len - 2).toFloat()
                if (s[len - 1] == 'h') return f * luaContext.height / 100
                if (s[len - 1] == 'w') return f * luaContext.width / 100
            }
            val t = s.substring(len - 2)
            val i = types[t]
            if (i != null) {
                val n = s.substring(0, len - 2)
                return TypedValue.applyDimension(i, n.toInt().toFloat(), dm)
            }
        }
        /*if (s.matches("^-?\\d+\\p{Alpha}+$")) {
        String n = s.replaceAll("\\p{Alpha}+$", "");
        String t = s.replaceAll("^-?\\d+", "");
        if (types.containsKey(t)) {
            return TypedValue.applyDimension(types.get(t), Integer.parseInt(n), dm);
        }
    }*/
        try {
            return s.toLong()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            return s.toDouble()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return s
    }

    @JvmOverloads
    fun load(
        layout: LuaValue, env: LuaTable = LuaTable(), params: LuaValue =
            ViewGroup.LayoutParams::class.java.toLuaValue()
    ): LuaValue {
        var params = params
        val viewClass = layout[1]
        if (viewClass.isnil()) throw LuaError(
            """
                loadlayout error: First value Must be a Class, checked import package.
                
                at ${layout.checktable().dump()}
                """.trimIndent()
        )
        val isAdapterView =
            viewClass.isuserdata() && AdapterView::class.java.isAssignableFrom(
                viewClass.touserdata(
                    Class::class.java
                )
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
                            // v = mContext.touserdata(LuaContext.class).getLuaState().package_.require.call(v);
                            if (isAdapterView) {
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

                                    else -> {}
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
                                val views = tValue.checktable()
                                val list = mutableListOf<View>()
                                val luaContext = luaContext
                                for (i in 1 until views.length() + 1) {  // 从1开始，避免i+1的使用
                                    val v = views[i]
                                    when {
                                        v.isuserdata() -> list.add(v.toView())
                                        v.istable() -> list.add(
                                            load(
                                                v.checktable(),
                                                env
                                            ).touserdata(View::class.java)
                                        )

                                        v.isstring() -> {
                                            list.add(
                                                load(
                                                    luaContext.luaState.require(v),
                                                    env
                                                ).toView()
                                            )
                                        }
                                    }
                                }
                                view["setAdapter"].jcall(LuaPagerAdapter(list))
                                continue
                            }

                            "pagesWithTitle" -> {
                                val (views, titles) = tValue.checktable().let {
                                    it[1].checktable() to it[2].checktable()
                                }

                                val viewList = mutableListOf<View>()
                                val titleList = mutableListOf<String>()
                                val luaContext = luaContext

                                for (i in 1 until views.length() + 1) {
                                    val v = views[i]
                                    when {
                                        v.isuserdata() -> viewList.add(v.toView())
                                        v.istable() -> viewList.add(
                                            load(
                                                v.checktable(),
                                                env
                                            ).toView()
                                        )

                                        v.isstring() -> viewList.add(
                                            load(
                                                luaContext.luaState.require(
                                                    v
                                                ), env
                                            ).toView()
                                        )
                                    }
                                }
                                generateSequence(1) { it + 1 }
                                    .takeWhile { it <= titles.length() }
                                    .map { titles[it].asString() }
                                    .toCollection(titleList)
                                view["setAdapter"].jcall(LuaPagerAdapter(viewList, titleList))
                                continue
                            }

                            "src" -> {
                                try {
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
                                } catch (e: Exception) {
                                    e.printStackTrace()
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
                                when (tValue.asString()) {
                                    "@string/appbar_scrolling_view_behavior" -> {
                                        params["setBehavior"].jcall(AppBarLayout.ScrollingViewBehavior())
                                    }

                                    "@string/bottom_sheet_behavior" -> {
                                        params["setBehavior"].jcall(BottomSheetBehavior<View>())
                                    }

                                    "@string/side_sheet_behavior" -> {
                                        params["setBehavior"].jcall(SideSheetBehavior<View>())
                                    }

                                    "@string/hide_bottom_view_on_scroll_behavior" -> {
                                        params["setBehavior"].jcall(
                                            HideBottomViewOnScrollBehavior<View>()
                                        )
                                    }

                                    else -> {
                                        params["setBehavior"].jcall(tValue)
                                    }
                                }
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
    }
}

package com.androlua

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Build
import android.text.TextUtils
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ImageView.ScaleType
import androidx.appcompat.view.ContextThemeWrapper
import coil.ComponentRegistry
import coil.ImageLoader
import coil.decode.GifDecoder
import coil.decode.ImageDecoderDecoder
import coil.decode.SvgDecoder
import coil.request.ImageRequest
import com.androlua.adapter.ArrayListAdapter
import com.androlua.adapter.LuaAdapter
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.behavior.HideBottomViewOnScrollBehavior
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.sidesheet.SideSheetBehavior
import com.nekolaksa.asString
import com.nekolaksa.firstArg
import com.nekolaksa.ifNotNil
import com.nekolaksa.isNotNil
import com.nekolaksa.secondArg
import com.nekolaksa.toLuaValue
import com.nekolaksa.toVarargs
import github.daisukiKaffuChino.LuaPagerAdapter
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.LuaValue.NIL
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceLuaToJava
import java.util.Locale

//inline fun <T : View> T.onClick(crossinline onClick: (v: T) -> Unit) {
//    setOnClickListener { onClick(it as T) }
//}

/**
 * Created by nirenr on 2019/11/18.
 */
class LuaLayout(private val realContext: Context) {
    private val dm: DisplayMetrics = realContext.resources.displayMetrics
    private val views = HashMap<String, LuaValue>()
    private val luaContext: LuaValue = realContext.toLuaValue()
    private val imageLoader: ImageLoader = ImageLoader.Builder(realContext).components(
        ComponentRegistry.Builder().apply {
            if (Build.VERSION.SDK_INT >= 28) {
                add(ImageDecoderDecoder.Factory())
            } else {
                add(GifDecoder.Factory())
            }
            add(SvgDecoder.Factory())
        }.build()
    ).build()
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
                return f * luaContext.touserdata(LuaContext::class.java).width / 100
            }

            if (s[len - 2] == '%') {
                val f = s.substring(0, len - 2).toFloat()
                if (s[len - 1] == 'h') return f * luaContext.touserdata(LuaContext::class.java).height / 100
                if (s[len - 1] == 'w') return f * luaContext.touserdata(LuaContext::class.java).width / 100
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
        val cls = layout[1]
        if (cls.isnil()) throw LuaError(
            """
                loadlayout error: Fist value Must be a Class, checked import package.
                
                at ${layout.checktable().dump()}
                """.trimIndent()
        )
        val isAdapterView =
            cls.isuserdata() && AdapterView::class.java.isAssignableFrom(
                cls.touserdata(
                    Class::class.java
                )
            )
        val view = layout["style"].run {
            if (isNotNil()) cls.call(
                ContextThemeWrapper(realContext, toint()).toLuaValue(),
                NIL,
                this
            ) else cls.call(luaContext)
        }
        params = params.call(W, W)
        try {
            var key = NIL
            var next: Varargs
            while (!layout.next(key).also { next = it }.isnil(1)) {
                try {
                    key = next.firstArg()
                    if (key.isint()) {
                        if (key.toint() > 1) {
                            var v = next.secondArg()
                            if (v.isstring()) v =
                                luaContext.touserdata(LuaContext::class.java).luaState.p.y.call(
                                    v
                                )
                            // v =
                            // mContext.touserdata(LuaContext.class).getLuaState().package_.require.call(v);
                            if (isAdapterView) {
                                view.jset(
                                    "adapter",
                                    LuaAdapter(
                                        luaContext.touserdata(LuaContext::class.java),
                                        v.checktable()
                                    )
                                )
                            } else {
                                v = load(v, env, cls["LayoutParams"])
                                view["addView"].call(v)
                            }
                        }
                    } else if (key.isstring()) {
                        var k = key.asString()
                        var `val` = next.secondArg()

                        when (k) {
                            "padding" -> continue
                            "id" -> {
                                view["id"] = idx
                                views[`val`.asString()] = view
                                ids[`val`.asString()] = idx
                                env[`val`] = view
                                idx++
                                continue
                            }

                            "text" -> {
                                view["text"] = `val`.tostring()
                                continue
                            }

                            "textSize" -> {
                                view["setTextSize"].jcall(0, toValue(`val`.asString()))
                                continue
                            }

                            "textStyle" -> {
                                when (`val`.asString()) {
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
                                    .jcall(scaleTypeValues[scaleType[`val`.asString()]!!])
                                continue
                            }

                            "ellipsize" -> {
                                view["setEllipsize"]
                                    .jcall(
                                        TextUtils.TruncateAt.valueOf(
                                            `val`.asString().uppercase(
                                                Locale.getDefault()
                                            )
                                        )
                                    )
                                continue
                            }

                            "hint" -> {
                                view["hint"] = `val`.tostring()
                                continue
                            }

                            "items" -> {
                                val adapter = view["adapter"]
                                if (adapter.isNotNil()) {
                                    adapter["addAll"].call(`val`)
                                } else {
                                    view["setAdapter"]
                                        .jcall(
                                            ArrayListAdapter(
                                                realContext,
                                                android.R.layout.simple_list_item_1,
                                                CoerceLuaToJava.arrayCoerce(
                                                    `val`,
                                                    String::class.java
                                                ) as Array<*>
                                            )
                                        )
                                }
                                continue
                            }

                            "minHeight" -> {
                                view["MinimumHeight"] = `val`.tostring()
                                continue
                            }

                            "minWidth" -> {
                                view["MinimumWidth"] = `val`.tostring()
                                continue
                            }

                            "pages" -> {
                                val ts = `val`.checktable()
                                val list = ArrayList<View>()
                                var i = 0
                                while (i < ts.length()) {
                                    val v = ts[i + 1]
                                    if (v.isuserdata()) {
                                        list.add(v.touserdata(View::class.java))
                                    } else if (v.istable()) {
                                        list.add(
                                            load(v.checktable(), env).touserdata(
                                                View::class.java
                                            )
                                        )
                                    } else if (v.isstring()) {
                                        list.add(
                                            load(
                                                luaContext.touserdata(LuaContext::class.java).luaState.p.y.call(
                                                    v
                                                ), env
                                            )
                                                .touserdata(View::class.java)
                                        )
                                    }
                                    i++
                                }
                                view["setAdapter"].jcall(LuaPagerAdapter(list))
                                continue
                            }

                            "pagesWithTitle" -> {
                                val tab = `val`.checktable()
                                val views = tab[1].checktable()
                                val titles = tab[2].checktable()
                                val viewList = ArrayList<View>()
                                val titleList = ArrayList<String>()
                                run {
                                    var i = 0
                                    while (i < views.length()) {
                                        val v = views[i + 1]
                                        if (v.isuserdata()) {
                                            viewList.add(v.touserdata(View::class.java))
                                        } else if (v.istable()) {
                                            viewList.add(
                                                load(v.checktable(), env).touserdata(
                                                    View::class.java
                                                )
                                            )
                                        } else if (v.isstring()) {
                                            viewList.add(
                                                load(
                                                    luaContext.touserdata(LuaContext::class.java).luaState.p.y.call(
                                                        v
                                                    ), env
                                                )
                                                    .touserdata(View::class.java)
                                            )
                                        }
                                        i++
                                    }
                                }
                                var i = 0
                                while (i < titles.length()) {
                                    val v = titles[i + 1]
                                    titleList.add(v.touserdata(String::class.java))
                                    i++
                                }
                                view["setAdapter"].jcall(LuaPagerAdapter(viewList, titleList))
                                continue
                            }

                            "src" -> {
                                try {
                                    if (`val`.isuserdata(Bitmap::class.java)) {
                                        view.jset(
                                            "ImageBitmap", `val`.touserdata(
                                                Bitmap::class.java
                                            )
                                        )
                                    } else if (`val`.isuserdata(Drawable::class.java)) {
                                        view.jset(
                                            "ImageDrawable", `val`.touserdata(
                                                Drawable::class.java
                                            )
                                        )
                                    } else {
                                        // if (src.startsWith("http")) {
                                        //                      new AsyncTaskX<String, String, Bitmap>() {
                                        //                        @Override
                                        //                        protected Bitmap a(String... strings) {
                                        //                          try {
                                        //                            return LuaBitmap.getHttpBitmap(context, src);
                                        //                          } catch (Exception e) {
                                        //                            e.printStackTrace();
                                        //                            return null;
                                        //                          }
                                        //                        }
                                        //
                                        //                        @Override
                                        //                        protected void a(Bitmap bitmap) {
                                        //                          if (bitmap != null) view.jset("ImageBitmap",
                                        // bitmap);
                                        //                        }
                                        //                      }.execute();
                                        imageLoader.enqueue(
                                            ImageRequest.Builder(realContext)
                                                .data(`val`.asString()).target {
                                                    view.jset("ImageDrawable", it)
                                                }.build()
                                        )
                                        // } else {
                                        //                      view.jset(
                                        //                          "ImageBitmap",
                                        //
                                        // LuaBitmap.getBitmap(mContext.touserdata(LuaContext.class), src));
                                        // }
                                    }
                                } catch (e: Exception) {
                                    e.printStackTrace()
                                }
                                continue
                            }

                            "background" -> {
                                if (`val`.isuserdata()) {
                                    view.jset(
                                        "background", `val`.touserdata(
                                            Drawable::class.java
                                        )
                                    )
                                } else if (`val`.isnumber()) {
                                    view.jset("backgroundColor", `val`.toint())
                                } else if (`val`.isstring()) {
                                    val str = `val`.asString()
                                    if (str.startsWith("#")) {
                                        val clr = parseColor(str)
                                        view.jset("backgroundColor", clr)
                                    } else {
                                        view.jset(
                                            "background",
                                            LuaBitmapDrawable(
                                                luaContext.touserdata(LuaContext::class.java),
                                                str
                                            )
                                        )
                                    }
                                }
                                continue
                            }

                            else -> if (k.startsWith("on")) {
                                if (`val`.isstring()) {
                                    val finalVal = `val`
                                    `val` = object : VarArgFunction() {
                                        override fun invoke(args: Varargs): Varargs {
                                            return env[finalVal].invoke(args)
                                        }
                                    }
                                }
                                view[key] = `val`
                            }
                        }
                        if (`val`.type() == LuaValue.TSTRING) {
                            `val` = toValue(`val`.asString()).toLuaValue()
                        }
                        if (k.startsWith("layout")) {
                            if (rules.containsKey(k)) {
                                if (`val`.isboolean() && `val`.toboolean()) params["addRule"].jcall(
                                    rules[k]
                                )
                                else if (`val`.asString() == "true") params["addRule"].jcall(
                                    rules[k]
                                )
                                else params["addRule"].jcall(rules[k], ids[`val`.asString()])
                            } else if (k == "layout_behavior") {
                                when (`val`.asString()) {
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
                                        params["setBehavior"].jcall(`val`)
                                    }
                                }
                            } else if (k == "layout_anchor") {
                                params["setAnchorId"].jcall(ids[`val`.asString()])
                            } else if (k == "layout_collapseParallaxMultiplier") {
                                params["setParallaxMultiplier"].jcall(`val`)
                            } else if (k == "layout_marginEnd") {
                                params["setMarginEnd"].jcall(`val`)
                            } else if (k == "layout_marginStart") {
                                params["setMarginStart"].jcall(`val`)
                            } else if (k == "layout_collapseMode") {
                                params["setCollapseMode"].jcall(`val`)
                            } else if (k == "layout_scrollFlags") {
                                params["setScrollFlags"].jcall(`val`)
                            } else {
                                k = k.substring(7)
                                params[k] = `val`
                            }
                        } else {
                            view[key] = `val`
                        }
                    }
                } catch (e: Exception) {
                    luaContext
                        .touserdata(LuaContext::class.java)
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
                    if (pt.isnil()) pt = layout["layout_margin"]
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
                    if (pt.isnil()) pt = layout["padding"]
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
                    .touserdata(LuaContext::class.java)
                    .sendError("loadlayout " + layout.checktable().dump(), it as Exception)
                it.printStackTrace()
            }
        } catch (e: Exception) {
            luaContext.touserdata(LuaContext::class.java)
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
            toint["scroll"] = 1
            toint["exitUtilCollapsed"] = 2
            toint["enterAlways"] = 4
            toint["enterAlwaysCollapsed"] = 8
            toint["snap"] = 16

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
        private val W: LuaValue = ViewGroup.LayoutParams.WRAP_CONTENT.toLuaValue()

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

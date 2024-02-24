package com.androlua;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ImageView;

import androidx.appcompat.view.ContextThemeWrapper;

import com.androlua.adapter.ArrayListAdapter;
import com.androlua.adapter.LuaAdapter;

import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.Varargs;
import org.luaj.lib.VarArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;
import org.luaj.lib.jse.CoerceLuaToJava;

import java.util.ArrayList;
import java.util.HashMap;

import coil.ComponentRegistry;
import coil.ImageLoader;
import coil.decode.GifDecoder;
import coil.decode.ImageDecoderDecoder;
import coil.decode.SvgDecoder;
import coil.request.ImageRequest;
import github.daisukiKaffuChino.LuaPagerAdapter;

/**
 * Created by nirenr on 2019/11/18.
 */
public class LuaLayout {

    private static final HashMap<String, Integer> toint = new HashMap<>();

    static {
        // android:drawingCacheQuality
        toint.put("auto", 0);
        toint.put("low", 1);
        toint.put("high", 2);

        // android:importantForAccessibility
        // toint.put("auto", 0);
        toint.put("yes", 1);
        toint.put("no", 2);

        // android:layerType
        toint.put("none", 0);
        toint.put("software", 1);
        toint.put("hardware", 2);

        // android:layoutDirection
        toint.put("ltr", 0);
        toint.put("rtl", 1);
        toint.put("inherit", 2);
        toint.put("locale", 3);

        // android:scrollbarStyle
        toint.put("insideOverlay", 0x0);
        toint.put("insideInset", 0x01000000);
        toint.put("outsideOverlay", 0x02000000);
        toint.put("outsideInset", 0x03000000);

        // android:visibility
        toint.put("visible", 0);
        toint.put("invisible", 4);
        toint.put("gone", 8);

        toint.put("wrap_content", -2);
        toint.put("fill_parent", -1);
        toint.put("match_parent", -1);
        toint.put("wrap", -2);
        toint.put("fill", -1);
        toint.put("match", -1);

        // android:autoLink
        // toint.put("none", 0x00);
        toint.put("web", 0x01);
        toint.put("email", 0x02);
        toint.put("phon", 0x04);
        toint.put("toint", 0x08);
        toint.put("all", 0x0f);

        // android:orientation
        toint.put("vertical", 1);
        toint.put("horizontal", 0);

        // android:gravity
        toint.put("axis_clip", 8);
        toint.put("axis_pull_after", 4);
        toint.put("axis_pull_before", 2);
        toint.put("axis_specified", 1);
        toint.put("axis_x_shift", 0);
        toint.put("axis_y_shift", 4);
        toint.put("bottom", 80);
        toint.put("center", 17);
        toint.put("center_horizontal", 1);
        toint.put("center_vertical", 16);
        toint.put("clip_horizontal", 8);
        toint.put("clip_vertical", 128);
        toint.put("display_clip_horizontal", 16777216);
        toint.put("display_clip_vertical", 268435456);
        // toint.put("fill",119);
        toint.put("fill_horizontal", 7);
        toint.put("fill_vertical", 112);
        toint.put("horizontal_gravity_mask", 7);
        toint.put("left", 3);
        toint.put("no_gravity", 0);
        toint.put("relative_horizontal_gravity_mask", 8388615);
        toint.put("relative_layout_direction", 8388608);
        toint.put("right", 5);
        toint.put("start", 8388611);
        toint.put("top", 48);
        toint.put("vertical_gravity_mask", 112);
        toint.put("end", 8388613);

        // android:textAlignment
        toint.put("inherit", 0);
        toint.put("gravity", 1);
        toint.put("textStart", 2);
        toint.put("textEnd", 3);
        toint.put("textCenter", 4);
        toint.put("viewStart", 5);
        toint.put("viewEnd", 6);

        // android:inputType
        // toint.put("none", 0x00000000);
        toint.put("text", 0x00000001);
        toint.put("textCapCharacters", 0x00001001);
        toint.put("textCapWords", 0x00002001);
        toint.put("textCapSentences", 0x00004001);
        toint.put("textAutoCorrect", 0x00008001);
        toint.put("textAutoComplete", 0x00010001);
        toint.put("textMultiLine", 0x00020001);
        toint.put("textImeMultiLine", 0x00040001);
        toint.put("textNoSuggestions", 0x00080001);
        toint.put("textUri", 0x00000011);
        toint.put("textEmailAddress", 0x00000021);
        toint.put("textEmailSubject", 0x00000031);
        toint.put("textShortMessage", 0x00000041);
        toint.put("textLongMessage", 0x00000051);
        toint.put("textPersonName", 0x00000061);
        toint.put("textPostalAddress", 0x00000071);
        toint.put("textPassword", 0x00000081);
        toint.put("textVisiblePassword", 0x00000091);
        toint.put("textWebEditText", 0x000000a1);
        toint.put("textFilter", 0x000000b1);
        toint.put("textPhonetic", 0x000000c1);
        toint.put("textWebEmailAddress", 0x000000d1);
        toint.put("textWebPassword", 0x000000e1);
        toint.put("number", 0x00000002);
        toint.put("numberSigned", 0x00001002);
        toint.put("numberDecimal", 0x00002002);
        toint.put("numberPassword", 0x00000012);
        toint.put("phone", 0x00000003);
        toint.put("datetime", 0x00000004);
        toint.put("date", 0x00000014);
        toint.put("time", 0x00000024);

        // android:imeOptions
        toint.put("normal", 0x00000000);
        toint.put("actionUnspecified", 0x00000000);
        toint.put("actionNone", 0x00000001);
        toint.put("actionGo", 0x00000002);
        toint.put("actionSearch", 0x00000003);
        toint.put("actionSend", 0x00000004);
        toint.put("actionNext", 0x00000005);
        toint.put("actionDone", 0x00000006);
        toint.put("actionPrevious", 0x00000007);
        toint.put("flagNoFullscreen", 0x2000000);
        toint.put("flagNavigatePrevious", 0x4000000);
        toint.put("flagNavigateNext", 0x8000000);
        toint.put("flagNoExtractUi", 0x10000000);
        toint.put("flagNoAccessoryAction", 0x20000000);
        toint.put("flagNoEnterAction", 0x40000000);
        toint.put("flagForceAscii", 0x80000000);

        // layout_scrollFlags
        toint.put("scroll", 1);
        toint.put("exitUtilCollapsed", 2);
        toint.put("enterAlways", 4);
        toint.put("enterAlwaysCollapsed", 8);
        toint.put("snap", 16);

        // layout_collapseMode
        toint.put("pin", 1);
        toint.put("parallax", 2);
    }

    private static final HashMap<String, Integer> scaleType = new HashMap<>();

    static {
        // android:scaleType
        scaleType.put("matrix", 0);
        scaleType.put("fitXY", 1);
        scaleType.put("fitStart", 2);
        scaleType.put("fitCenter", 3);
        scaleType.put("fitEnd", 4);
        scaleType.put("center", 5);
        scaleType.put("centerCrop", 6);
        scaleType.put("centerInside", 7);
    }

    private static final HashMap<String, Integer> rules = new HashMap<>();

    static {
        toint.put("layout_above", 2);
        rules.put("layout_alignBaseline", 4);
        rules.put("layout_alignBottom", 8);
        rules.put("layout_alignEnd", 19);
        rules.put("layout_alignLeft", 5);
        rules.put("layout_alignParentBottom", 12);
        rules.put("layout_alignParentEnd", 21);
        rules.put("layout_alignParentLeft", 9);
        rules.put("layout_alignParentRight", 11);
        rules.put("layout_alignParentStart", 20);
        rules.put("layout_alignParentTop", 10);
        rules.put("layout_alignRight", 7);
        rules.put("layout_alignStart", 18);
        rules.put("layout_alignTop", 6);
        rules.put("layout_alignWithParentIfMissing", 0);
        rules.put("layout_below", 3);
        rules.put("layout_centerHorizontal", 14);
        rules.put("layout_centerInParent", 13);
        rules.put("layout_centerVertical", 15);
        rules.put("layout_toEndOf", 17);
        rules.put("layout_toLeftOf", 0);
        rules.put("layout_toRightOf", 1);
        rules.put("layout_toStartOf", 16);
    }

    private static final HashMap<String, Integer> types = new HashMap<>();

    static {
        types.put("px", 0);
        types.put("dp", 1);
        types.put("sp", 2);
        types.put("pt", 3);
        types.put("in", 4);
        types.put("mm", 5);
    }

    private static final HashMap<String, Integer> ids = new HashMap<>();
    private final DisplayMetrics dm;
    private HashMap<String, LuaValue> views = new HashMap<>();
    private static int idx = 0x7f000000;

    private static final String[] ps =
            new String[]{"paddingLeft", "paddingTop", "paddingRight", "paddingBottom"};
    private static final String[] ms =
            new String[]{
                    "layout_marginLeft", "layout_marginTop", "layout_marginRight", "layout_marginBottom"
            };
    private static final LuaValue W = CoerceJavaToLua.coerce(ViewGroup.LayoutParams.WRAP_CONTENT);

    private final LuaValue mContext;

    private final Context realContext;

    private final ImageLoader imageLoader;

    private final ImageView.ScaleType[] scaleTypeValues = ImageView.ScaleType.values();

    public LuaLayout(Context context) {
        realContext = context;
        mContext = CoerceJavaToLua.coerce(context);
        dm = context.getResources().getDisplayMetrics();
        ComponentRegistry.Builder builder = new ComponentRegistry.Builder();
        if (Build.VERSION.SDK_INT >= 28) {
            builder.add(new ImageDecoderDecoder.Factory());
        } else {
            builder.add(new GifDecoder.Factory());
        }
        builder.add(new SvgDecoder.Factory());
        imageLoader = new ImageLoader.Builder(context).components(builder.build()).build();
    }

    public HashMap getId() {
        return ids;
    }

    public HashMap getView() {
        return views;
    }

    public int type() {
        return LuaValue.TUSERDATA;
    }

    public String typename() {
        return "LuaLayout";
    }

    public LuaValue get(LuaValue key) {
        return get(key.tojstring());
    }

    public LuaValue get(String key) {
        return getView(key);
    }

    public LuaValue getView(String id) {
        return views.get(id);
    }

    public Object toint(String s) {
        if (s.equals("nil")) return 0;
        int len = s.length();

        if (s.contains("|")) {
            String[] ss = s.split("\\|");
            int ret = 0;
            for (String s1 : ss) {
                if (toint.containsKey(s1)) ret |= toint.get(s1);
            }
            return ret;
        }
        if (toint.containsKey(s)) return toint.get(s);

        if (len > 2) {
            if (s.charAt(0) == '#') {
                try {
                    return Color.parseColor(s);
                } catch (Exception e) {
                    int clr = Integer.parseInt(s.substring(1), 16);
                    if (s.length() < 6) return clr | 0xff000000;
                    return clr;
                }
            }
            if (s.charAt(len - 1) == '%') {
                float f = Float.parseFloat(s.substring(0, len - 1));
                return f * mContext.touserdata(LuaContext.class).getWidth() / 100;
            }

            if (s.charAt(len - 2) == '%') {
                float f = Float.parseFloat(s.substring(0, len - 2));
                if (s.charAt(len - 1) == 'h')
                    return f * mContext.touserdata(LuaContext.class).getHeight() / 100;
                if (s.charAt(len - 1) == 'w')
                    return f * mContext.touserdata(LuaContext.class).getWidth() / 100;
            }
            String t = s.substring(len - 2);
            Integer i = types.get(t);
            if (i != null) {
                String n = s.substring(0, len - 2);
                return TypedValue.applyDimension(i, Integer.parseInt(n), dm);
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
            return Long.parseLong(s);
        } catch (Exception e) {
            e.printStackTrace();
        }
        try {
            return Double.parseDouble(s);
        } catch (Exception e) {

            e.printStackTrace();
        }
        return s;
    }

    public static int parseColor(String colorString) {
        if (colorString.charAt(0) == '#') {
            // Use a long to avoid rollovers on #ffXXXXXX
            long color = Long.parseLong(colorString.substring(1), 16);
            if (colorString.length() <= 7) {
                // Set the alpha value
                color |= 0x00000000ff000000L;
            }
            return (int) color;
        }
        return 0;
    }

    public LuaValue load(LuaValue layout) {
        return load(layout, new LuaTable(), CoerceJavaToLua.coerce(ViewGroup.LayoutParams.class));
    }

    public LuaValue load(LuaValue layout, LuaTable env) {
        return load(layout, env, CoerceJavaToLua.coerce(ViewGroup.LayoutParams.class));
    }

    public LuaValue load(LuaValue layout, LuaTable env, LuaValue params) {
        LuaValue cls = layout.get(1);
        if (cls.isnil())
            throw new LuaError(
                    "loadlayout error: Fist value Must be a Class, checked import package.\n\nat "
                            + layout.checktable().dump());
        boolean isAdapterView =
                cls.isuserdata() && AdapterView.class.isAssignableFrom(cls.touserdata(Class.class));
        LuaValue style = layout.get("style");
        LuaValue view;
        if (style != LuaValue.NIL) {
            view =
                    cls.call(
                            CoerceJavaToLua.coerce(
                                    new ContextThemeWrapper(realContext, style.toint())),
                            LuaValue.NIL,
                            style
                    );
        } else {
            view = cls.call(mContext);
        }
        params = params.call(W, W);
        try {
            LuaValue key = LuaValue.NIL;
            Varargs next;
            while (!(next = layout.next(key)).isnil(1)) {
                try {
                    key = next.arg1();
                    if (key.isint()) {
                        if (key.toint() > 1) {
                            LuaValue v = next.arg(2);
                            if (v.isstring())
                                v = mContext.touserdata(LuaContext.class).getLuaState().p.y.call(v);
                            // v =
                            // mContext.touserdata(LuaContext.class).getLuaState().package_.require.call(v);
                            if (isAdapterView) {
                                view.jset(
                                        "adapter",
                                        new LuaAdapter(mContext.touserdata(LuaContext.class), v.checktable()));
                            } else {
                                v = load(v, env, cls.get("LayoutParams"));
                                view.get("addView").call(v);
                            }
                        }
                    } else if (key.isstring()) {
                        String k = key.tojstring();
                        LuaValue val = next.arg(2);

                        switch (k) {
                            case "padding":
                                continue;
                            case "id":
                                view.set("id", idx);
                                views.put(val.tojstring(), view);
                                ids.put(val.tojstring(), idx);
                                env.set(val, view);
                                idx++;
                                continue;
                            case "text":
                                view.set("text", val.tostring());
                                continue;
                            case "textSize":
                                view.get("setTextSize").jcall(0, toint(val.tojstring()));
                                continue;
                            case "textStyle":
                                String textStyle = val.tojstring();
                                switch (textStyle) {
                                    case "bold" ->
                                            view.get("setTypeface").jcall(Typeface.defaultFromStyle(Typeface.BOLD));
                                    case "normal" ->
                                            view.get("setTypeface").jcall(Typeface.defaultFromStyle(Typeface.NORMAL));
                                    case "italic" ->
                                            view.get("setTypeface").jcall(Typeface.defaultFromStyle(Typeface.ITALIC));
                                    case "italic|bold", "bold|italic" ->
                                            view.get("setTypeface").jcall(Typeface.defaultFromStyle(Typeface.BOLD_ITALIC));
                                }
                                continue;
                            case "scaleType":
                                view.get("setScaleType")
                                        .jcall(scaleTypeValues[scaleType.get(val.tojstring())]);
                                continue;
                            case "ellipsize":
                                view.get("setEllipsize")
                                        .jcall(TextUtils.TruncateAt.valueOf(val.tojstring().toUpperCase()));
                                continue;
                            case "hint":
                                view.set("hint", val.tostring());
                                continue;
                            case "items":
                                LuaValue adapter = view.get("adapter");
                                if (!adapter.isnil()) {
                                    adapter.get("addAll").call(val);
                                } else {
                                    view.get("setAdapter")
                                            .jcall(
                                                    new ArrayListAdapter<>(
                                                            realContext,
                                                            android.R.layout.simple_list_item_1,
                                                            (String[]) CoerceLuaToJava.arrayCoerce(val, String.class)));
                                }
                                continue;
                            case "minHeight":
                                view.set("MinimumHeight", val.tostring());
                                continue;
                            case "minWidth":
                                view.set("MinimumWidth", val.tostring());
                                continue;
                            case "pages":
                                LuaTable ts = val.checktable();
                                int len = ts.length();
                                ArrayList<View> list = new ArrayList<>();
                                for (int i = 0; i < len; i++) {
                                    LuaValue v = ts.get(i + 1);
                                    if (v.isuserdata()) {
                                        list.add(v.touserdata(View.class));
                                    } else if (v.istable()) {
                                        list.add(load(v.checktable(), env).touserdata(View.class));
                                    } else if (v.isstring()) {
                                        list.add(
                                                load(mContext.touserdata(LuaContext.class).getLuaState().p.y.call(v), env)
                                                        .touserdata(View.class));
                                    }
                                }
                                view.get("setAdapter").jcall(new LuaPagerAdapter(list));
                                continue;
                            case "pagesWithTitle":
                                LuaTable tab = val.checktable();
                                LuaTable vtab = tab.get(1).checktable();
                                LuaTable titles = tab.get(2).checktable();
                                int len2 = vtab.length();
                                ArrayList<View> list2 = new ArrayList<>();
                                int titlelen = titles.length();
                                ArrayList<String> titleList = new ArrayList<>();
                                for (int i = 0; i < len2; i++) {
                                    LuaValue v = vtab.get(i + 1);
                                    if (v.isuserdata()) {
                                        list2.add(v.touserdata(View.class));
                                    } else if (v.istable()) {
                                        list2.add(load(v.checktable(), env).touserdata(View.class));
                                    } else if (v.isstring()) {
                                        list2.add(
                                                load(mContext.touserdata(LuaContext.class).getLuaState().p.y.call(v), env)
                                                        .touserdata(View.class));
                                    }
                                }
                                for (int i = 0; i < titlelen; i++) {
                                    LuaValue v = titles.get(i + 1);
                                    titleList.add(v.touserdata(String.class));
                                }
                                view.get("setAdapter").jcall(new LuaPagerAdapter(list2, titleList));
                                continue;
                                //              case "pages":
                                //                LuaTable ts = val.checktable();
                                //                int len = ts.length();
                                //                View[] vs = new View[len];
                                //                for (int i = 0; i < len; i++) {
                                //                  LuaValue v = ts.get(i + 1);
                                //                  if (v.isuserdata()) {
                                //                    vs[i] = v.touserdata(View.class);
                                //                  } else if (v.istable()) {
                                //                    vs[i] = load(v.checktable(),
                                // env).touserdata(View.class);
                                //                  } else if (v.isstring()) {
                                //                    vs[i] =
                                //
                                // load(mContext.touserdata(LuaContext.class).getLuaState().p.y.call(v), env)
                                //                            .touserdata(View.class);
                                //                  }
                                //                }
                                //                view.get("setAdapter").jcall(new
                                // ArrayPageAdapter(vs));
                                //                continue;
                            case "src":
                                try {
                                    if (val.isuserdata(Bitmap.class)) {
                                        view.jset("ImageBitmap", val.touserdata(Bitmap.class));
                                    } else if (val.isuserdata(Drawable.class)) {
                                        view.jset("ImageDrawable", val.touserdata(Drawable.class));
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
                                                new ImageRequest.Builder(realContext).data(val.tojstring()).target(
                                                        new LuaTarget(view)
                                                ).build()
                                        );
                                        // } else {
                                        //                      view.jset(
                                        //                          "ImageBitmap",
                                        //
                                        // LuaBitmap.getBitmap(mContext.touserdata(LuaContext.class), src));
                                        // }
                                    }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                                continue;
                            case "background":
                                if (val.isuserdata()) {
                                    view.jset("background", val.touserdata(Drawable.class));
                                } else if (val.isnumber()) {
                                    view.jset("backgroundColor", val.toint());
                                } else if (val.isstring()) {
                                    String s = val.tojstring();
                                    if (s.startsWith("#")) {
                                        int clr = parseColor(s);
                                        view.jset("backgroundColor", clr);
                                    } else {
                                        view.jset(
                                                "background",
                                                new LuaBitmapDrawable(mContext.touserdata(LuaContext.class), s));
                                    }
                                }
                                continue;
                            default:
                                if (k.startsWith("on")) {
                                    if (val.isstring()) {
                                        final LuaValue finalVal = val;
                                        val =
                                                new VarArgFunction() {
                                                    @Override
                                                    public Varargs invoke(Varargs args) {
                                                        return env.get(finalVal).invoke(args);
                                                    }
                                                };
                                    }
                                    view.set(key, val);
                                }
                        }

                        if (val.type() == LuaValue.TSTRING) {
                            String s = val.tojstring();
                            val = CoerceJavaToLua.coerce(toint(s));
                        }
                        if (k.startsWith("layout")) {
                            if (rules.containsKey(k)) {
                                if (val.isboolean() && val.toboolean())
                                    params.get("addRule").jcall(rules.get(k));
                                else if (val.tojstring().equals("true"))
                                    params.get("addRule").jcall(rules.get(k));
                                else
                                    params.get("addRule").jcall(rules.get(k), ids.get(val.tojstring()));
                            } else if (k.equals("layout_behavior")) {
                                if (val.tojstring().equals("@string/appbar_scrolling_view_behavior")) {
                                    params
                                            .get("setBehavior")
                                            .jcall(
                                                    new com.google.android.material.appbar.AppBarLayout
                                                            .ScrollingViewBehavior());
                                } else if (val.tojstring().equals("@string/bottom_sheet_behavior")) {
                                    params
                                            .get("setBehavior")
                                            .jcall(new com.google.android.material.bottomsheet.BottomSheetBehavior<>());
                                } else {
                                    params.get("setBehavior").jcall(val);
                                }
                            } else if (k.equals("layout_anchor")) {
                                params.get("setAnchorId").jcall(ids.get(val.tojstring()));
                            } else if (k.equals("layout_collapseParallaxMultiplier")) {
                                params.get("setParallaxMultiplier").jcall(val);
                            } else if (k.equals("layout_marginEnd")) {
                                params.get("setMarginEnd").jcall(val);
                            } else if (k.equals("layout_marginStart")) {
                                params.get("setMarginStart").jcall(val);
                            } else if (k.equals("layout_collapseMode")) {
                                params.get("setCollapseMode").jcall(val);
                            } else if (k.equals("layout_scrollFlags")) {
                                params.get("setScrollFlags").jcall(val);
                            } else {
                                k = k.substring(7);
                                params.set(k, val);
                            }
                        } else {
                            view.set(key, val);
                        }
                    }
                } catch (Exception e) {
                    mContext
                            .touserdata(LuaContext.class)
                            .sendError("loadlayout " + view + ": " + next.arg1() + "=" + next.arg(2), e);
                    e.printStackTrace();
                }
            }

            try {
                LuaValue[] mss = new LuaValue[4];
                boolean sp = false;
                for (int i = 0; i < ms.length; i++) {
                    LuaValue pt = layout.get(ms[i]);
                    if (pt.isnil()) pt = layout.get("layout_margin");
                    if (pt.isnil()) {
                        pt = view.get(pt);
                    } else {
                        sp = true;
                    }
                    mss[i] = CoerceJavaToLua.coerce(toint(pt.tojstring()));
                }
                if (sp) {
                    LuaValue setMargins = params.get("setMargins");
                    if (!setMargins.isnil()) setMargins.invoke(LuaValue.varargsOf(mss));
                }
            } catch (Exception e) {
                e.printStackTrace();
            }

            view.set("LayoutParams", params);
            try {
                LuaValue[] pds = new LuaValue[4];
                boolean sp = false;
                for (int i = 0; i < ps.length; i++) {
                    LuaValue pt = layout.get(ps[i]);
                    if (pt.isnil()) pt = layout.get("padding");
                    if (pt.isnil()) {
                        pt = view.get(pt);
                    } else {
                        sp = true;
                    }
                    pds[i] = CoerceJavaToLua.coerce(toint(pt.tojstring()));
                }
                if (sp) view.get("setPadding").invoke(LuaValue.varargsOf(pds));
            } catch (Exception e) {
                mContext
                        .touserdata(LuaContext.class)
                        .sendError("loadlayout " + layout.checktable().dump(), e);

                e.printStackTrace();
            }

        } catch (Exception e) {
            mContext.touserdata(LuaContext.class).sendError("loadlayout " + layout.checktable().dump(), e);
            e.printStackTrace();
        }
        return view;
    }
}

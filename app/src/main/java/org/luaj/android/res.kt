package org.luaj.android;

import android.content.res.Configuration;
import android.graphics.Typeface;

import com.androlua.LuaActivity;
import com.androlua.LuaBitmap;
import com.androlua.LuaBitmapDrawable;
import com.androlua.LuaContext;
import com.androlua.LuaLayout;

import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.lib.TwoArgFunction;
import org.luaj.lib.jse.CoerceJavaToLua;

import java.io.File;
import java.util.Locale;

public final class res extends TwoArgFunction {

    private final LuaContext context;
    private String mLanguage;
    private Globals globals;
    private LuaTable colorTable;
    private Configuration configuration;

    public res(LuaContext ctx) {
        this.context = ctx;
        mLanguage = Locale.getDefault().getLanguage();
        if (ctx instanceof LuaActivity activity) {
            configuration = activity.getResources().getConfiguration();
        }
    }

    public LuaValue call(LuaValue modName, LuaValue env) {
        globals = env.checkglobals();
        LuaTable res = new LuaTable();
        res.set("string", new string(context));
        res.set("drawable", new drawable(context));
        res.set("bitmap", new bitmap(context));
        res.set("layout", new layout(context));
        res.set("view", new view(context));
        res.set("font", new font(context));
        if (configuration != null) {
            res.set("dimen", new dimen(context, configuration));
            res.set("color", new color(context, configuration));
        }
        env.set("res", res);
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("res", res);
        return NIL;
    }

    private final class dimen extends LuaValue {
        private LuaTable dimenTable;
        private final Configuration configuration;
        private final LuaContext activity;

        public dimen(LuaContext ctx, Configuration configuration) {
            this.configuration = configuration;
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaTable checktable() {
            dimenTable = new LuaTable();
            String path = activity.getLuaPath("res/dimen", "init.lua");
            if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
            switch (configuration.orientation) {
                case Configuration.ORIENTATION_PORTRAIT:
                    path = activity.getLuaPath("res/dimen", "port.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_LANDSCAPE:
                    path = activity.getLuaPath("res/dimen", "land.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_SQUARE:
                    path = activity.getLuaPath("res/dimen", "square.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_UNDEFINED:
                    path = activity.getLuaPath("res/dimen", "undefined.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
            }
            return dimenTable;
        }

        @Override
        public LuaValue get(String key) {
            if (dimenTable != null) return dimenTable.get(key);
            dimenTable = new LuaTable();
            String path = activity.getLuaPath("res/dimen", "init.lua");
            if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
            switch (configuration.orientation) {
                case Configuration.ORIENTATION_PORTRAIT:
                    path = activity.getLuaPath("res/dimen", "port.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_LANDSCAPE:
                    path = activity.getLuaPath("res/dimen", "land.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_SQUARE:
                    path = activity.getLuaPath("res/dimen", "square.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
                case Configuration.ORIENTATION_UNDEFINED:
                    path = activity.getLuaPath("res/dimen", "undefined.lua");
                    if (new File(path).exists()) globals.loadfile(path, dimenTable).call();
                    break;
            }
            return dimenTable.get(key);
        }
    }


    private final class color extends LuaValue {
        private final Configuration configuration;
        private final LuaContext activity;

        private boolean isDarkMode() {
            return (configuration.uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        }

        public color(LuaContext ctx, Configuration configuration) {
            this.configuration = configuration;
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaTable checktable() {
            colorTable = new LuaTable();
            String path = activity.getLuaPath("res/color", "init.lua");
            if (new File(path).exists()) globals.loadfile(path, colorTable).call();
            if (isDarkMode()) {
                path = activity.getLuaPath("res/color", "night.lua");
            } else {
                path = activity.getLuaPath("res/color", "day.lua");
            }
            if (new File(path).exists()) globals.loadfile(path, colorTable).call();
            return colorTable;
        }

        @Override
        public LuaValue get(String key) {
            if (colorTable != null) return colorTable.get(key);
            colorTable = new LuaTable();
            String path = activity.getLuaPath("res/color", "init.lua");
            if (new File(path).exists()) globals.loadfile(path, colorTable).call();
            if (isDarkMode()) {
                path = activity.getLuaPath("res/color", "night.lua");
            } else {
                path = activity.getLuaPath("res/color", "day.lua");
            }
            if (new File(path).exists()) globals.loadfile(path, colorTable).call();
            return colorTable.get(key);
        }
    }

    private final class string extends LuaValue {
        private final LuaContext activity;
        private LuaTable stringTable;

        public string(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaTable checktable() {
            String language = Locale.getDefault().getLanguage();
            if (!language.equals(mLanguage)) {
                mLanguage = language;
                stringTable = null;
            }
            if (stringTable == null) {
                stringTable = new LuaTable();
                String p = activity.getLuaPath("res/string", "init.lua");
                if (new File(p).exists()) globals.loadfile(p, stringTable).call();

                // 加载指定语言的字符串资源文件
                p = activity.getLuaPath("res/string", mLanguage + ".lua");
                if (new File(p).exists()) {
                    globals.loadfile(p, stringTable).call();
                } else {
                    // 如果当前设备的语言不存在对应的资源文件，则加载默认的语言资源文件
                    p = activity.getLuaPath("res/string", "default.lua");
                    if (new File(p).exists()) {
                        LuaValue defValue = globals.loadfile(p).call();
                        if (defValue.isstring()) {
                            String defLanguage = defValue.tojstring();
                            p = activity.getLuaPath("res/string", defLanguage + ".lua");
                            if (new File(p).exists()) {
                                globals.loadfile(p, stringTable).call();
                            }
                        }
                    }
                }
            }
            return stringTable;
        }

        @Override
        public LuaValue get(String key) {
            if (stringTable != null) return stringTable.get(key);
            String language = Locale.getDefault().getLanguage();
            if (!language.equals(mLanguage)) {
                mLanguage = language;
                stringTable = null;
            }
            if (stringTable == null) {
                stringTable = new LuaTable();
                String p = activity.getLuaPath("res/string", "init.lua");
                if (new File(p).exists()) globals.loadfile(p, stringTable).call();
                // 加载指定语言的字符串资源文件
                p = activity.getLuaPath("res/string", mLanguage + ".lua");
                if (new File(p).exists()) {
                    globals.loadfile(p, stringTable).call();
                } else {
                    // 如果当前设备的语言不存在对应的资源文件，则加载默认的语言资源文件
                    p = activity.getLuaPath("res/string", "default.lua");
                    if (new File(p).exists()) {
                        LuaValue defValue = globals.loadfile(p).call();
                        if (defValue.isstring()) {
                            String defLanguage = defValue.tojstring();
                            p = activity.getLuaPath("res/string", defLanguage + ".lua");
                            if (new File(p).exists()) {
                                globals.loadfile(p, stringTable).call();
                            }
                        }
                    }
                }
            }
            return stringTable.get(key);
        }
    }

    private final class drawable extends LuaValue {
        private final LuaContext activity;

        drawable(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/drawable")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/drawable", arg);
            if (new File(p + ".png").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".png"));
            if (new File(p + ".jpg").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".jpg"));
            if (new File(p + ".gif").exists())
                return CoerceJavaToLua.coerce(new LuaBitmapDrawable(activity, p + ".gif"));
            if (new File(p + ".lua").exists()) return globals.loadfile(p + ".lua", globals).call();
            return LuaValue.NIL;
        }
    }

    private final class bitmap extends LuaValue {
        private final LuaContext activity;

        bitmap(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/drawable")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            try {
                String p = activity.getLuaPath("res/drawable", arg);
                if (new File(p + ".png").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".png"));
                if (new File(p + ".jpg").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".jpg"));
                if (new File(p + ".gif").exists())
                    return CoerceJavaToLua.coerce(LuaBitmap.getBitmap(activity, p + ".gif"));
                if (new File(p + ".lua").exists())
                    return globals.loadfile(p + ".lua", globals).call();
                return LuaValue.NIL;
            } catch (Exception e) {
                throw new LuaError(e);
            }
        }
    }

    private final class layout extends LuaValue {
        private final LuaContext activity;

        layout(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/layout")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/layout", arg + ".lua");
            return globals.loadfile(p, globals).call();
        }
    }

    private final class view extends LuaValue {
        private final LuaContext activity;

        view(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/layout")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            String p = activity.getLuaPath("res/layout", arg + ".lua");
            return new LuaLayout(activity.getContext())
                    .load(globals.loadfile(p, globals).call(), globals);
        }
    }

    private final class font extends LuaValue {
        private final LuaContext activity;

        font(LuaContext ctx) {
            this.activity = ctx;
        }

        @Override
        public int type() {
            return LuaValue.TTABLE;
        }

        @Override
        public String typename() {
            return "table";
        }

        @Override
        public LuaTable checktable() {
            LuaTable t = new LuaTable();
            String[] p = new File(activity.getLuaPath("res/font")).list();
            if (p != null) {
                for (int i = 0; i < p.length; i++) {
                    t.set(i + 1, p[i]);
                }
            }
            return t;
        }

        @Override
        public LuaValue get(LuaValue key) {
            return get(key.tojstring());
        }

        @Override
        public LuaValue get(String arg) {
            try {
                String p = activity.getLuaPath("res/font", arg);
                if (new File(p + ".ttf").exists())
                    return CoerceJavaToLua.coerce(Typeface.createFromFile(new File(p + ".ttf")));
                if (new File(p + ".otf").exists())
                    return CoerceJavaToLua.coerce(Typeface.createFromFile(new File(p + ".otf")));
                return LuaValue.NIL;
            } catch (Exception e) {
                throw new LuaError(e);
            }
        }
    }
}

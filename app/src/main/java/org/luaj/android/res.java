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

public class res extends TwoArgFunction {

  private String mLanguage;
  private Globals glabals;
  private LuaTable stringTable;
  private final LuaContext activity;
  private LuaTable dimenTable;
  private Integer orientation;

  public res(LuaContext activity) {
    this.activity = activity;
    mLanguage = Locale.getDefault().getLanguage();
    if (activity instanceof LuaActivity context) {
        orientation = context.getResources().getConfiguration().orientation;
    }
  }

  public LuaValue call(LuaValue modname, LuaValue env) {
    glabals = env.checkglobals();
    LuaTable res = new LuaTable();
    res.set("string", new string());
    res.set("drawable", new drawable());
    res.set("bitmap", new bitmap());
    res.set("layout", new layout());
    res.set("view", new view());
    res.set("font", new font());
    if (orientation != null) {
      res.set("dimen", new dimen());
    }
    env.set("res", res);
    if (!env.get("package").isnil()) env.get("package").get("loaded").set("res", res);
    return NIL;
  }

  private class dimen extends LuaValue {

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
      dimenTable = null;
      LuaTable defTable = new LuaTable();
      String p = activity.getLuaPath("res/dimen", "init.lua");
      if (new File(p).exists()) glabals.loadfile(p, defTable).call();
      dimenTable = defTable.clone();

      if (orientation == Configuration.ORIENTATION_PORTRAIT) {
        p = activity.getLuaPath("res/dimen", "port.lua");
        if (new File(p).exists()) glabals.loadfile(p, dimenTable).call();
      } else if (orientation == Configuration.ORIENTATION_LANDSCAPE) {
        p = activity.getLuaPath("res/dimen", "land.lua");
        if (new File(p).exists()) glabals.loadfile(p, dimenTable).call();
      }

      return dimenTable;
    }

    @Override
    public LuaValue get(String key) {
      dimenTable = null;
      LuaTable defTable = new LuaTable();
      String p = activity.getLuaPath("res/dimen", "init.lua");
      if (new File(p).exists()) glabals.loadfile(p, defTable).call();
      dimenTable = defTable.clone();

      if (orientation == Configuration.ORIENTATION_PORTRAIT) {
        p = activity.getLuaPath("res/dimen", "port.lua");
        if (new File(p).exists()) glabals.loadfile(p, dimenTable).call();
      } else if (orientation == Configuration.ORIENTATION_LANDSCAPE) {
        p = activity.getLuaPath("res/dimen", "land.lua");
        if (new File(p).exists()) glabals.loadfile(p, dimenTable).call();
      }

      return dimenTable.get(key);
    }
  }

  private class string extends LuaValue {

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
        LuaTable defTable = new LuaTable();
        String p = activity.getLuaPath("res/string", "init.lua");
        if (new File(p).exists()) glabals.loadfile(p, defTable).call();
        stringTable = defTable.clone();

        p = activity.getLuaPath("res/string", mLanguage + ".lua");
        if (new File(p).exists()) glabals.loadfile(p, stringTable).call();
      }
      return stringTable;
    }
    //
    //    @Override
    //    public LuaValue get(String key) {
    //      String language = Locale.getDefault().getLanguage();
    //      if (!language.equals(mLanguage)) {
    //        mLanguage = language;
    //        stringTable = null;
    //      }
    //      if (stringTable == null) {
    //        LuaTable defTable = new LuaTable();
    //        String p = activity.getLuaPath("res/string", "init.lua");
    //        if (new File(p).exists()) glabals.loadfile(p, defTable).call();
    //        stringTable = defTable.clone();
    //
    //        p = activity.getLuaPath("res/string", mLanguage + ".lua");
    //        if (new File(p).exists()) glabals.loadfile(p, stringTable).call();
    //      }
    //      return stringTable.get(key);
    //    }
    @Override
    public LuaValue get(String key) {
      String language = Locale.getDefault().getLanguage();
      if (!language.equals(mLanguage)) {
        mLanguage = language;
        stringTable = null;
      }
      if (stringTable == null) {
        LuaTable defTable = new LuaTable();
        String p = activity.getLuaPath("res/string", "init.lua");
        if (new File(p).exists()) glabals.loadfile(p, defTable).call();
        stringTable = defTable.clone();

        // 加载指定语言的字符串资源文件
        p = activity.getLuaPath("res/string", mLanguage + ".lua");
        if (new File(p).exists()) {
          glabals.loadfile(p, stringTable).call();
        } else {
          // 如果当前设备的语言不存在对应的资源文件，则加载默认的语言资源文件
          p = activity.getLuaPath("res/string", "default.lua");
          if (new File(p).exists()) {
            LuaValue defValue = glabals.loadfile(p).call();
            if (defValue.isstring()) {
              String defLanguage = defValue.tojstring();
              p = activity.getLuaPath("res/string", defLanguage + ".lua");
              if (new File(p).exists()) {
                glabals.loadfile(p, stringTable).call();
              }
            }
          }
        }
      }
      return stringTable.get(key);
    }
  }

  private class drawable extends LuaValue {
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
      if (new File(p + ".lua").exists()) return glabals.loadfile(p + ".lua", glabals).call();
      return LuaValue.NIL;
    }
  }

  private class bitmap extends LuaValue {
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
        if (new File(p + ".lua").exists()) return glabals.loadfile(p + ".lua", glabals).call();
        return LuaValue.NIL;
      } catch (Exception e) {
        throw new LuaError(e);
      }
    }
  }

  private class layout extends LuaValue {
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
      return glabals.loadfile(p, glabals).call();
    }
  }

  private class view extends LuaValue {
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
          .load(glabals.loadfile(p, glabals).call(), glabals);
    }
  }

  private class font extends LuaValue {
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

package com.androlua;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Environment;
import androidx.preference.PreferenceManager;
import com.google.android.material.color.DynamicColors;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import org.luaj.Globals;
import org.luaj.LuaTable;

/** Created by nirenr on 2019/12/13. */
public class LuaApplication extends Application implements LuaContext {
  private static LuaApplication instance;
  private String mExtDir;
  private static final HashMap sGlobalData = new HashMap();

  public static LuaApplication getInstance() {
    return instance;
  }

  @Override
  public void onCreate() {
    super.onCreate();
    instance = this;
    rmDir(getExternalFilesDir("dexfiles"));
    CrashHandler.getInstance().init(this);
    DynamicColors.applyToActivitiesIfAvailable(this);
  }

  public static boolean rmDir(File dir) {
    if (dir.isDirectory()) {
      File[] fs = dir.listFiles();
      for (File f : fs) rmDir(f);
    }
    return dir.delete();
  }

  @Override
  public ArrayList<ClassLoader> getClassLoaders() {
    return null;
  }

  @Override
  public void call(String func, Object... args) {}

  @Override
  public void set(String name, Object value) {}

  @Override
  public String getLuaPath() {
    return null;
  }

  public String getLuaPath(String s) {
    return new File(getLuaDir(), s).getAbsolutePath();
  }

  @Override
  public String getLuaPath(String dir, String name) {
    return null;
  }

  public String getLuaDir() {
    return getFilesDir().getAbsolutePath();
  }

  @Override
  public String getLuaDir(String dir) {
    return null;
  }

  public String getLuaExtDir() {
    if (mExtDir != null) return mExtDir;
    File d = new File(Environment.getExternalStorageDirectory(), "LuaJ");
    if (!d.exists()) d.mkdirs();
    mExtDir = d.getAbsolutePath();
    return mExtDir;
  }

  @Override
  public String getLuaExtDir(String dir) {
    File d = new File(getLuaExtDir(), dir);
    if (!d.exists()) d.mkdirs();
    return d.getAbsolutePath();
  }

  @Override
  public void setLuaExtDir(String dir) {
    mExtDir = dir;
  }

  @Override
  public String getLuaExtPath(String path) {
    return new File(getLuaExtDir(), path).getAbsolutePath();
  }

  @Override
  public String getLuaExtPath(String dir, String name) {
    return new File(getLuaExtDir(dir), name).getAbsolutePath();
  }

  @Override
  public Context getContext() {
    return this;
  }

  @Override
  public Globals getLuaState() {
    return null;
  }

  @Override
  public Object doFile(String path, Object... arg) {
    return null;
  }

  @Override
  public void sendMsg(String msg) {}

  @Override
  public void sendError(String title, Exception msg) {}

  @Override
  public int getWidth() {
    return 0;
  }

  @Override
  public int getHeight() {
    return 0;
  }

  @Override
  public Map getGlobalData() {
    return sGlobalData;
  }

  @Override
  public Map<String, ?> getSharedData() {
    return PreferenceManager.getDefaultSharedPreferences(this).getAll();
  }

  @Override
  public Object getSharedData(String key) {
    return PreferenceManager.getDefaultSharedPreferences(this).getAll().get(key);
  }

  @Override
  public Object getSharedData(String key, Object def) {
    Object ret = PreferenceManager.getDefaultSharedPreferences(this).getAll().get(key);
    if (ret != null) return ret;
    return def;
  }

  @Override
  public boolean setSharedData(String key, Object value) {
    SharedPreferences.Editor edit = PreferenceManager.getDefaultSharedPreferences(this).edit();
    if (value == null) edit.remove(key);
    else if (value instanceof String) edit.putString(key, value.toString());
    else if (value instanceof Long) edit.putLong(key, (Long) value);
    else if (value instanceof Integer) edit.putInt(key, (Integer) value);
    else if (value instanceof Float) edit.putFloat(key, (Float) value);
    else if (value instanceof LuaTable)
      edit.putStringSet(key, new HashSet(((LuaTable) value).values()));
    else if (value instanceof Set) edit.putStringSet(key, (Set<String>) value);
    else if (value instanceof Boolean) edit.putBoolean(key, (Boolean) value);
    else return false;
    return edit.commit();
  }

  @Override
  public void regGc(LuaGcable obj) {}

  @Override
  public InputStream findResource(String name) {
    try {
      if (new File(name).exists()) return new FileInputStream(name);
    } catch (Exception e) {
      /*
      e.printStackTrace();*/
    }
    try {
      return new FileInputStream(new File(getLuaPath(name)));
    } catch (Exception e) {
      /*
      e.printStackTrace();*/
    }
    try {
      return getAssets().open(name);
    } catch (Exception ioe) {
      /*
      e.printStackTrace();*/
    }
    return null;
  }

  public boolean checkResource(String name) {
    try {
      if (new File(name).exists()) return true;
    } catch (Exception e) {

    }
    try {
      return new File(getLuaPath(name)).exists();
    } catch (Exception e) {
      /*
      e.printStackTrace();*/
    }
    try {
      InputStream in = getAssets().open(name);
      in.close();
      return true;
    } catch (Exception ioe) {

    }
    return false;
  }

  @Override
  public String findFile(String filename) {
    if (filename.startsWith("/")) return filename;
    return getLuaPath(filename);
  }
}

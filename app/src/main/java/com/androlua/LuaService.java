package com.androlua;

import android.annotation.SuppressLint;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Build;
import android.os.Environment;
import android.os.IBinder;
import android.os.StrictMode;
import android.provider.MediaStore;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.WindowManager;
import android.webkit.MimeTypeMap;
import android.widget.Toast;
import androidx.core.content.FileProvider;
import androidx.preference.PreferenceManager;
import com.androlua.adapter.ArrayListAdapter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import org.luaj.Globals;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.android.file;
import org.luaj.android.http;
import org.luaj.android.json;
import org.luaj.android.loadlayout;
import org.luaj.android.print;
import org.luaj.android.printf;
import org.luaj.android.res;
import org.luaj.android.task;
import org.luaj.android.thread;
import org.luaj.android.timer;
import org.luaj.lib.ResourceFinder;
import org.luaj.lib.jse.JavaPackage;
import org.luaj.lib.jse.JsePlatform;

public class LuaService extends Service
    implements ResourceFinder, LuaContext, LuaBroadcastReceiver.OnReceiveListener {
  private static final String ARG = "arg";
  private static final String DATA = "data";
  private static final String NAME = "name";

  private static LuaService sInstance = null;
  private static String mLuaDir;
  private SurfaceHolder mHolder;

  public SurfaceHolder getHolder() {
    return mHolder;
  }

  public static LuaService getInstance() {
    return sInstance;
  }

  public static void setEnabled(Context context) {
    Intent intent = new Intent(context, LuaService.class);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      context.startForegroundService(intent);
    } else {
      context.startService(intent);
    }
  }

  public static void setLuaDir(String path) {
    mLuaDir = path;
  }

  @Override
  public void onCreate() {
    StrictMode.ThreadPolicy policy = new StrictMode.ThreadPolicy.Builder().permitAll().build();
    StrictMode.setThreadPolicy(policy);
    setTheme(android.R.style.Theme_DeviceDefault);
    super.onCreate();
    sInstance = this;
  }

  private Globals globals;
  private final StringBuilder toastbuilder = new StringBuilder();
  private Toast toast;
  private long lastShow;
  private ArrayListAdapter<String> adapter;
  private String mExtDir;
  private int mWidth;
  private int mHeight;
  private boolean debug;
  private String luaDir;
  private String luaFile = "service.lua";
  private ArrayList<String> permissions;
  private boolean isSetViewed;
  private LuaDexLoader mLuaDexLoader;
  private ArrayList<LuaGcable> mGc = new ArrayList<>();
  private LuaBroadcastReceiver mReceiver;
  private String pageName = "main";

  @CallLuaFunction
  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    Uri d = intent.getData();
    // Log.i("luaj", "onCreate: "+d);
    if (mLuaDir != null) luaDir = mLuaDir;
    else luaDir = getFilesDir().getAbsolutePath();
    if (d != null) {
      String p = d.getPath();
      if (!TextUtils.isEmpty(p)) {
        File f = new File(p);
        if (f.isFile()) {
          p = f.getParent();
          luaFile = f.getAbsolutePath();
        }
        luaDir = p;
      }
    }
    luaDir = checkProjectDir(new File(luaDir)).getAbsolutePath();
    reStart();
    return super.onStartCommand(intent, flags, startId);
  }

  @CallLuaFunction
  public void reStart() {
    initSize();
    pageName = new File(luaFile).getName();
    int idx = pageName.lastIndexOf(".");
    if (idx > 0) pageName = pageName.substring(0, idx);

    mLuaDexLoader = new LuaDexLoader(this, luaDir);
    mLuaDexLoader.loadLibs();
    globals = JsePlatform.standardGlobals();
    globals.m = this;
    initENV();
    globals.s.e = mLuaDexLoader.getClassLoaders();
    try {
      globals.jset("notification", this);
      globals.jset("service", this);
      globals.jset("this", this);
      globals.set("print", new print(this));
      globals.set("printf", new printf(this));
      globals.set("loadlayout", new loadlayout(this));
      globals.set("task", new task(this));
      globals.set("thread", new thread(this));
      globals.set("timer", new timer(this));
      globals.load(new res(this));
      globals.load(new json());
      globals.load(new file());
      globals.jset("Http", Http.class);
      globals.jset("http", http.class);
      globals.set("android", new JavaPackage("android"));
      globals.set("java", new JavaPackage("java"));
      globals.set("com", new JavaPackage("com"));
      globals.set("org", new JavaPackage("org"));
      globals.loadfile(luaFile).jcall();
      runFunc("onCreate");
    } catch (final Exception e) {
      sendError("Error", e);
      e.printStackTrace();
      Intent res = new Intent();
      res.putExtra(DATA, e.toString());
    }
  }

  private File checkProjectDir(File dir) {
    if (dir == null) return new File(luaDir);
    if (new File(dir, "main.lua").exists() && new File(dir, "init.lua").exists()) return dir;
    return checkProjectDir(dir.getParentFile());
  }

  private void initENV() {
    if (!new File(luaDir + "/init.lua").exists()) return;

    try {
      LuaTable env = new LuaTable();
      globals.loadfile("init.lua", env).call();

      LuaValue debug = env.get("debugmode");
      if (debug.isboolean()) setDebug(debug.toboolean());
      debug = env.get("debug_mode");
      if (debug.isboolean()) setDebug(debug.toboolean());
      LuaValue theme = env.get("theme");
      if (theme.isint()) setTheme((int) theme.toint());
      else if (theme.isstring())
        setTheme(android.R.style.class.getField(theme.tojstring()).getInt(null));
    } catch (Exception e) {
      sendMsg(e.getMessage());
    }
  }

  public void showLogs() {
    LuaActivity sActivity = LuaActivity.sActivity;
    if (sActivity != null) {
      sActivity.showLogs();
    }
  }

  public void setDebug(boolean bool) {
    debug = bool;
  }

  private void initSize() {
    WindowManager wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
    DisplayMetrics outMetrics = new DisplayMetrics();
    wm.getDefaultDisplay().getMetrics(outMetrics);
    mWidth = outMetrics.widthPixels;
    mHeight = outMetrics.heightPixels;
  }

  public Object runFunc(String name, Object... arg) {
    try {
      LuaValue func = globals.get(name);
      if (func.isfunction()) return func.jcall(arg);
    } catch (Exception e) {
      sendError(name, e);
    }
    return null;
  }

  @Override
  public InputStream findResource(String name) {
    try {
      if (new File(name).exists()) return new FileInputStream(name);
    } catch (Exception e) {
      /*if (BuildConfig.DEBUG)
      e.printStackTrace();*/
    }
    try {
      return new FileInputStream(new File(getLuaPath(name)));
    } catch (Exception e) {
      /*if (BuildConfig.DEBUG)
      e.printStackTrace();*/
    }

    try {
      return getAssets().open(name);
    } catch (Exception ioe) {
      /*if (BuildConfig.DEBUG)
      e.printStackTrace();*/
    }
    return null;
  }

  @Override
  public String findFile(String filename) {
    if (filename.startsWith("/")) return filename;
    return getLuaPath(filename);
  }

  // 显示toast
  @SuppressLint("ShowToast")
  public void showToast(String text) {
    if (!debug) return;
    long now = System.currentTimeMillis();
    if (toast == null || now - lastShow > 1000) {
      toastbuilder.setLength(0);
      toast = Toast.makeText(this, text, Toast.LENGTH_LONG);
      toastbuilder.append(text);
      toast.show();
    } else {
      toastbuilder.append("\n");
      toastbuilder.append(text);
      toast.setText(toastbuilder.toString());
      toast.setDuration(Toast.LENGTH_LONG);
    }
    lastShow = now;
  }

  @Override
  public ArrayList<ClassLoader> getClassLoaders() {
    return null;
  }

  @Override
  public void call(String func, Object... args) {
    globals.get(func).jcall(args);
  }

  @Override
  public void set(String name, Object value) {
    globals.jset(name, value);
  }

  @Override
  public String getLuaPath() {
    return luaFile;
  }

  @Override
  public String getLuaPath(String path) {
    return new File(getLuaDir(), path).getAbsolutePath();
  }

  @Override
  public String getLuaPath(String dir, String name) {
    return new File(getLuaDir(dir), name).getAbsolutePath();
  }

  @Override
  public String getLuaDir() {
    return luaDir;
  }

  @Override
  public String getLuaDir(String dir) {
    return new File(getLuaDir(), dir).getAbsolutePath();
  }

  @Override
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
    return globals;
  }

  @Override
  public Object doFile(String path, Object... arg) {
    return globals.loadfile(path).jcall(arg);
  }

  @Override
  public void sendMsg(final String msg) {
    LuaActivity sActivity = LuaActivity.sActivity;
    if (sActivity != null) {
      sActivity.sendMsg(msg);
    } else {
      LuaActivity.logs.add(msg);
    }
  }

  @Override
  public void sendError(String title, Exception msg) {
    sendMsg(title + ": " + msg.getMessage());
  }

  public static void logError(String title, Exception msg) {
    LuaActivity.logs.add(title + ":" + msg);
  }

  public Intent registerReceiver(LuaBroadcastReceiver receiver, IntentFilter filter) {
    // TODO: Implement this method
    return super.registerReceiver(receiver, filter);
  }

  public Intent registerReceiver(LuaBroadcastReceiver.OnReceiveListener ltr, IntentFilter filter) {
    // TODO: Implement this method
    LuaBroadcastReceiver receiver = new LuaBroadcastReceiver(ltr);
    return super.registerReceiver(receiver, filter);
  }

  public Intent registerReceiver(IntentFilter filter) {
    // TODO: Implement this method
    if (mReceiver != null) unregisterReceiver(mReceiver);
    mReceiver = new LuaBroadcastReceiver(this);
    return super.registerReceiver(mReceiver, filter);
  }

  @Override
  public void unregisterReceiver(BroadcastReceiver receiver) {
    try {
      super.unregisterReceiver(receiver);
    } catch (Exception e) {
      Log.i("lua", "unregisterReceiver: " + receiver);
      e.printStackTrace();
    }
  }

  @CallLuaFunction
  @Override
  public void onReceive(Context context, Intent intent) {
    // TODO: Implement this method
    runFunc("onReceive", context, intent);
  }

  public static LuaActivity getActivity(String name) {
    return LuaActivity.getActivity(name);
  }

  @CallLuaFunction
  @Override
  public void onDestroy() {
    runFunc("onDestroy");
    for (LuaGcable g : mGc) {
      try {
        g.gc();
      } catch (Exception e) {

      }
    }
    mGc.clear();
    if (mReceiver != null) unregisterReceiver(mReceiver);

    super.onDestroy();
  }

  @Override
  public void onConfigurationChanged(Configuration newConfig) {
    // TODO: Implement this method
    super.onConfigurationChanged(newConfig);
    initSize();
  }

  @Override
  public IBinder onBind(Intent intent) {
    return new LuaBinder();
  }

  public class LuaBinder extends Binder {
    public LuaService getService() {
      return LuaService.this;
    }
  }

  public int getWidth() {
    return mWidth;
  }

  public int getHeight() {
    return mHeight;
  }

  @Override
  public Map getGlobalData() {
    return LuaApplication.getInstance().getGlobalData();
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
  public void regGc(LuaGcable obj) {
    mGc.add(obj);
  }

  public void newActivity(String path, boolean newDocument) throws FileNotFoundException {
    newActivity(1, path, null, newDocument);
  }

  public void newActivity(String path, Object[] arg, boolean newDocument)
      throws FileNotFoundException {
    newActivity(1, path, arg, newDocument);
  }

  public void newActivity(int req, String path, boolean newDocument) throws FileNotFoundException {
    newActivity(req, path, null, newDocument);
  }

  public void newActivity(String path) throws FileNotFoundException {
    newActivity(1, path, new Object[0]);
  }

  public void newActivity(String path, Object[] arg) throws FileNotFoundException {
    newActivity(1, path, arg);
  }

  public void newActivity(int req, String path) throws FileNotFoundException {
    newActivity(req, path, new Object[0]);
  }

  public void newActivity(int req, String path, Object[] arg) throws FileNotFoundException {
    newActivity(req, path, arg, false);
  }

  public void newActivity(int req, String path, Object[] arg, boolean newDocument)
      throws FileNotFoundException {
    // Log.i("luaj", "newActivity: "+path+ Arrays.toString(arg));
    Intent intent = new Intent(this, LuaActivity.class);
    if (newDocument) intent = new Intent(this, LuaActivityX.class);

    intent.putExtra(NAME, path);
    if (path.charAt(0) != '/' && luaDir != null) path = luaDir + "/" + path;
    File f = new File(path);
    if (f.isDirectory() && new File(path + "/main.lua").exists()) path += "/main.lua";
    else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua";
    if (!new File(path).exists()) throw new FileNotFoundException(path);

    if (newDocument) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT);
        intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
      }
    }

    intent.setData(Uri.parse("file://" + path));

    if (arg != null) intent.putExtra(ARG, arg);
    if (newDocument) startActivity(intent);
    else startActivity(intent);
  }

  public void newActivity(String path, int in, int out, boolean newDocument)
      throws FileNotFoundException {
    newActivity(1, path, in, out, null, newDocument);
  }

  public void newActivity(String path, int in, int out, Object[] arg, boolean newDocument)
      throws FileNotFoundException {
    newActivity(1, path, in, out, arg, newDocument);
  }

  public void newActivity(int req, String path, int in, int out, boolean newDocument)
      throws FileNotFoundException {
    newActivity(req, path, in, out, null, newDocument);
  }

  public void newActivity(String path, int in, int out) throws FileNotFoundException {
    newActivity(1, path, in, out, new Object[0]);
  }

  public void newActivity(String path, int in, int out, Object[] arg) throws FileNotFoundException {
    newActivity(1, path, in, out, arg);
  }

  public void newActivity(int req, String path, int in, int out) throws FileNotFoundException {
    newActivity(req, path, in, out, new Object[0]);
  }

  public void newActivity(int req, String path, int in, int out, Object[] arg)
      throws FileNotFoundException {
    newActivity(req, path, in, out, arg, false);
  }

  public void newActivity(int req, String path, int in, int out, Object[] arg, boolean newDocument)
      throws FileNotFoundException {
    Intent intent = new Intent(this, LuaActivity.class);
    if (newDocument) intent = new Intent(this, LuaActivityX.class);
    intent.putExtra(NAME, path);
    if (path.charAt(0) != '/' && luaDir != null) path = luaDir + "/" + path;
    File f = new File(path);
    if (f.isDirectory() && new File(path + "/main.lua").exists()) path += "/main.lua";
    else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua";
    if (!new File(path).exists()) throw new FileNotFoundException(path);

    intent.setData(Uri.parse("file://" + path));

    if (newDocument) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT);
        intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
      }
    }

    if (arg != null) intent.putExtra(ARG, arg);
    if (newDocument) startActivity(intent);
    else startActivity(intent);
  }

  @Override
  public void startActivity(Intent intent) {
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    super.startActivity(intent);
  }

  public Uri getUriForPath(String path) {
    return FileProvider.getUriForFile(this, getPackageName(), new File(path));
  }

  public Uri getUriForFile(File path) {
    return FileProvider.getUriForFile(this, getPackageName(), path);
  }

  public String getPathFromUri(Uri uri) {
    String path = null;
    if (uri != null) {
      String[] p = {MediaStore.Images.Media.DATA};
      switch (uri.getScheme()) {
        case "content":
          /*try {
                             InputStream in = getContentResolver().openInputStream(uri);
          } catch (IOException e) {
          	e.printStackTrace();
          }*/

          Cursor cursor = getContentResolver().query(uri, p, null, null, null);
          if (cursor != null) {
            int idx = cursor.getColumnIndexOrThrow(getPackageName());
            if (idx < 0) break;
            path = cursor.getString(idx);
            cursor.moveToFirst();
            cursor.close();
          }
          break;
        case "file":
          path = uri.getPath();
          break;
      }
    }
    return path;
  }

  private String getType(File file) {
    int lastDot = file.getName().lastIndexOf(46);
    if (lastDot >= 0) {
      String extension = file.getName().substring(lastDot + 1);
      String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
      if (mime != null) {
        return mime;
      }
    }
    return "application/octet-stream";
  }

  public void installApk(String path) {
    Intent share = new Intent(Intent.ACTION_VIEW);
    File file = new File(path);
    share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    share.setDataAndType(getUriForFile(file), getType(file));
    share.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    startActivity(share);
  }

  public void openFile(String path) {
    Intent share = new Intent(Intent.ACTION_VIEW);
    File file = new File(path);
    share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    share.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
    share.setDataAndType(getUriForFile(file), getType(file));
    share.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    startActivity(share);
  }

  public void shareFile(String path) {
    Intent share = new Intent(Intent.ACTION_SEND);
    File file = new File(path);
    share.setType("*/*");
    share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    share.putExtra(Intent.EXTRA_STREAM, getUriForFile(file));
    startActivity(
        Intent.createChooser(share, file.getName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  }
}

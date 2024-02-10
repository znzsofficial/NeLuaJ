package com.androlua;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.IBinder;
import android.os.StrictMode;
import android.provider.MediaStore;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.ContextMenu;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.MimeTypeMap;
import android.widget.ListView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatTextView;
import androidx.core.content.FileProvider;
import androidx.fragment.app.Fragment;
import androidx.preference.PreferenceManager;

import com.androlua.adapter.ArrayListAdapter;

import org.luaj.Globals;
import org.luaj.LuaError;
import org.luaj.LuaMetaTable;
import org.luaj.LuaTable;
import org.luaj.LuaValue;
import org.luaj.android.call;
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

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import dalvik.system.DexClassLoader;

public class LuaActivity extends AppCompatActivity
        implements ResourceFinder, LuaContext, LuaBroadcastReceiver.OnReceiveListener, LuaMetaTable {
    private static final String ARG = "arg";
    private static final String DATA = "data";
    private static final String NAME = "name";

    private Globals globals;
    private final StringBuilder toastbuilder = new StringBuilder();
    private Toast toast;
    private long lastShow;
    public static ArrayList<String> logs = new ArrayList<>();
    private ArrayListAdapter<String> adapter;
    private String mExtDir;
    private int mWidth;
    private int mHeight;
    private boolean debug;
    private String luaDir;
    private String luaFile = "main.lua";
    public static LuaActivity sActivity;
    private ArrayList<String> permissions;
    private boolean isSetViewed;
    private LuaDexLoader mLuaDexLoader;
    private ArrayList<LuaGcable> mGc = new ArrayList<>();
    private LuaBroadcastReceiver mReceiver;
    private String pageName = "main";
    private static final HashMap<String, LuaActivity> sLuaActivityMap = new HashMap<>();
    private LuaValue mOnKeyShortcut;
    private LuaValue mOnKeyDown;
    private LuaValue mOnKeyUp;
    private LuaValue mOnKeyLongPress;
    private LuaValue mOnTouchEvent;

    @CallLuaFunction
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri d = getIntent().getData();
        // Log.i("luaj", "onCreate: "+d);
        luaDir = getFilesDir().getAbsolutePath();
        if (d != null) {
            String p = d.getPath();
            if (!TextUtils.isEmpty(p)) {
                File f = new File(p);
                if (f.isFile()) {
                    p = f.getParent();
                    luaFile = f.getAbsolutePath();
                }
                luaDir = p;
                setTitle(new File(luaDir).getName());
            }
        }

        luaDir = checkProjectDir(new File(luaDir)).getAbsolutePath();
        initSize();
        pageName = new File(luaFile).getName();
        int idx = pageName.lastIndexOf(".");
        if (idx > 0) pageName = pageName.substring(0, idx);
        sLuaActivityMap.put(pageName, this);
        ListView mLogView = getLogView();
        mLuaDexLoader = new LuaDexLoader(this, luaDir);
        mLuaDexLoader.loadLibs();
        globals = JsePlatform.standardGlobals();
        // globals.finder = this;
        globals.m = this;
        initENV();
    /* globals.package_.searchers.insert(0,new VarArgFunction() {
        public Varargs invoke(Varargs args) {
            String classname = args.checkjstring(1);
            ArrayList<ClassLoader> lds = mLuaDexLoader.getClassLoaders();
            for (ClassLoader loader : lds) {
                try {
                    Class<?> cls = loader.loadClass(classname);
                    return CoerceJavaToLua.coerce(cls);
                } catch (ClassNotFoundException cnfe) {
                    return valueOf("\n\tno class '" + classname + "' "+loader);
                } catch (Exception e) {
                    return valueOf("\n\tjava load failed on '" + classname + "', " + e);
                }
            }
            return valueOf("\n\tno class '" + classname + "'");
        }
    });*/

        globals.s.e = mLuaDexLoader.getClassLoaders();
        sActivity = this;
        try {
            globals.jset("activity", this);
            globals.jset("this", this);
            globals.set("print", new print(this));
            globals.set("printf", new printf(this));
            globals.set("loadlayout", new loadlayout(this));
            globals.set("task", new task(this));
            globals.set("thread", new thread(this));
            globals.set("timer", new timer(this));
            globals.set("call", new call(this));
            globals.load(new res(this));
            globals.load(new json());
            globals.load(new file());
            globals.jset("Http", Http.class);
            globals.jset("http", http.class);
            globals.jset("R", github.znzsofficial.neluaj.R.class);
            globals.set("android", new JavaPackage("android"));
            globals.set("java", new JavaPackage("java"));
            globals.set("com", new JavaPackage("com"));
            globals.set("org", new JavaPackage("org"));
            Object[] arg = (Object[]) getIntent().getSerializableExtra(ARG);
            if (arg == null) arg = new Object[0];
            doFile(getLuaPath(), arg);
            runMainFunc(pageName, arg);
            runFunc("onCreate");
            if (!isSetViewed) setContentView(mLogView);
            mOnKeyShortcut = globals.get("onKeyShortcut");
            if (mOnKeyShortcut.isnil()) mOnKeyShortcut = null;
            mOnKeyDown = globals.get("onKeyDown");
            if (mOnKeyDown.isnil()) mOnKeyDown = null;
            mOnKeyUp = globals.get("onKeyUp");
            if (mOnKeyUp.isnil()) mOnKeyUp = null;
            mOnKeyLongPress = globals.get("onKeyLongPress");
            if (mOnKeyLongPress.isnil()) mOnKeyLongPress = null;
            mOnTouchEvent = globals.get("onTouchEvent");
            if (mOnTouchEvent.isnil()) mOnTouchEvent = null;
            if (getIntent().getBooleanExtra("isVersionChanged", false) && (savedInstanceState == null)) {
                runFunc(
                        "onVersionChanged",
                        getIntent().getStringExtra("newVersionName"),
                        getIntent().getStringExtra("oldVersionName"));
            }
        } catch (final Exception e) {
            sendError("Error", e);

            e.printStackTrace();
            setContentView(mLogView);
            Intent res = new Intent();
            res.putExtra(DATA, e.toString());
            setResult(-1, res);
        }
    }

    private ListView getLogView() {
        ListView list = new ListView(this);
        list.setFastScrollEnabled(true);
        list.setFastScrollAlwaysVisible(true);
        adapter =
                new ArrayListAdapter<String>(this, android.R.layout.simple_list_item_1) {
                    @Override
                    public View getView(int position, View convertView, ViewGroup parent) {
                        AppCompatTextView view =
                                (AppCompatTextView) super.getView(position, convertView, parent);
                        if (convertView == null) view.setTextIsSelectable(true);
                        return view;
                    }
                };
        list.setAdapter(adapter);
        return list;
    }

    ;

    public void setAllowThread(boolean bool) {
        if (bool == true) {
            StrictMode.ThreadPolicy policy = new StrictMode.ThreadPolicy.Builder().permitAll().build();
            StrictMode.setThreadPolicy(policy);
        } else {
            StrictMode.ThreadPolicy policy = new StrictMode.ThreadPolicy.Builder().detectAll().build();
            StrictMode.setThreadPolicy(policy);
        }
    }

    public Object runMainFunc(String name, Object[] arg) {
        try {
            LuaValue f = globals.get(name);
            if (f.isfunction()) return f.jcall(arg);
            f = globals.get("main");
            if (f.isfunction()) return f.jcall(arg);
        } catch (Exception e) {
            sendError(name, e);
        }
        return null;
    }

    @CallLuaFunction
    @Override
    public void onRequestPermissionsResult(
            int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        runFunc("onRequestPermissionsResult", requestCode, permissions, grantResults);
    }

    @CallLuaFunction
    @Override
    public boolean onKeyShortcut(int keyCode, KeyEvent event) {
        if (mOnKeyShortcut != null) {
            try {
                Object ret = mOnKeyShortcut.jcall(keyCode, event);
                if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return true;
            } catch (LuaError e) {
                sendError("onKeyShortcut", e);
            }
        }
        return super.onKeyShortcut(keyCode, event);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (mOnKeyDown != null) {
            try {
                Object ret = mOnKeyDown.jcall(keyCode, event);
                if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return true;
            } catch (LuaError e) {
                sendError("onKeyDown", e);
            }
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (mOnKeyUp != null) {
            try {
                Object ret = mOnKeyUp.jcall(keyCode, event);
                if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return true;
            } catch (LuaError e) {
                sendError("onKeyUp", e);
            }
        }
        return super.onKeyUp(keyCode, event);
    }

    @Override
    public boolean onKeyLongPress(int keyCode, KeyEvent event) {
        if (mOnKeyLongPress != null) {
            try {
                Object ret = mOnKeyLongPress.jcall(keyCode, event);
                if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return true;
            } catch (LuaError e) {
                sendError("onKeyLongPress", e);
            }
        }
        return super.onKeyLongPress(keyCode, event);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (mOnTouchEvent != null) {
            try {
                Object ret = mOnTouchEvent.jcall(event);
                if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return true;
            } catch (LuaError e) {
                sendError("onTouchEvent", e);
            }
        }
        return super.onTouchEvent(event);
    }

    private File checkProjectDir(File dir) {
        if (dir == null) return new File(luaDir);
        if (new File(dir, "main.lua").exists() && new File(dir, "init.lua").exists()) return dir;
        return checkProjectDir(dir.getParentFile());
    }

    protected void initENV() {
        if (!new File(luaDir + "/init.lua").exists()) return;

        try {
            LuaTable env = new LuaTable();
            globals.loadfile("init.lua", env).call();
            LuaValue title = env.get("appname");
            if (title.isstring()) setTitle(title.tojstring());
            title = env.get("app_name");
            if (title.isstring()) setTitle(title.tojstring());

            LuaValue debug = env.get("debugmode");
            if (debug.isboolean()) setDebug(debug.toboolean());
            debug = env.get("debug_mode");
            if (debug.isboolean()) setDebug(debug.toboolean());
            LuaValue theme = env.get("theme");
            if (theme.isint()) setTheme((int) theme.toint());
            else if (theme.isstring())
                setTheme(android.R.style.class.getField(theme.tojstring()).getInt(null));
            LuaValue jtheme = env.get("NeLuaJ_Theme");
            if (jtheme.isstring())
                setTheme(
                        github.znzsofficial.neluaj.R.style.class.getField(jtheme.tojstring()).getInt(null));
        } catch (Exception e) {
            sendMsg(e.getMessage());
        }
    }

    @Override
    public void setTitle(CharSequence title) {
        super.setTitle(title);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            ActivityManager.TaskDescription tDesc = null;
            // try {
            // tDesc =
            //     new ActivityManager.TaskDescription(
            //         title.toString(), LuaBitmap.getLocalBitmap(getLuaPath("icon.png")));
            // } catch (IOException e) {

            //   e.printStackTrace();
            tDesc = new ActivityManager.TaskDescription(title.toString());
            //     }
            setTaskDescription(tDesc);
        }
    }

    public void setContentView(LuaTable view) {
        isSetViewed = true;
        setContentView(new LuaLayout(this).load(view, globals).touserdata(View.class));
    }

    public void setFragment(Fragment fragment) {
        setContentView(new View(this));
        getSupportFragmentManager().beginTransaction().replace(android.R.id.content, fragment).commit();
    }

    public void showLogs() {
        new AlertDialog.Builder(this)
                .setTitle("Logs")
                .setAdapter(adapter, null)
                .setPositiveButton(android.R.string.ok, null)
                .create()
                .show();
    }

    public void setDebug(boolean bool) {
        debug = bool;
    }

    public ArrayList getLogs() {
        return logs;
    }

    public ArrayListAdapter getLogAdapter() {
        return adapter;
    }

    private void initSize() {
        WindowManager wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics outMetrics = new DisplayMetrics();
        wm.getDefaultDisplay().getMetrics(outMetrics);
        mWidth = outMetrics.widthPixels;
        mHeight = outMetrics.heightPixels;
    }

    public boolean checkAllPermissions() {
        if (Build.VERSION.SDK_INT >= 23) {
            if (checkCallingOrSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    != PackageManager.PERMISSION_GRANTED) {
                try {
                    permissions = new ArrayList<String>();
                    PackageManager pm = getPackageManager();
                    String[] ps2 =
                            pm.getPackageInfo(getPackageName(), PackageManager.GET_PERMISSIONS)
                                    .requestedPermissions;
                    for (String p : ps2) {
                        try {
                            if ((pm.getPermissionInfo(p, 0).protectionLevel & 1) != 0)
                                checkPermission(p);
                        } catch (Exception e) {

                            e.printStackTrace();
                        }
                    }
                    if (!permissions.isEmpty()) {
                        String[] ps = new String[permissions.size()];
                        permissions.toArray(ps);
                        requestPermissions(ps, 0);
                        return false;
                    }
                } catch (Exception e) {

                    e.printStackTrace();
                }
            }
        }
        return true;
    }

    private void checkPermission(String permission) {
        if (checkCallingOrSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            permissions.add(permission);
        }
    }

    @CallLuaFunction
    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        runFunc("onCreateOptionsMenu", menu);
        return true;
    }

    @CallLuaFunction
    @Override
    public void onCreateContextMenu(
            ContextMenu contextMenu, View view, ContextMenu.ContextMenuInfo contextMenuInfo) {
        runFunc("onCreateContextMenu", contextMenu, view, contextMenuInfo);
        super.onCreateContextMenu(contextMenu, view, contextMenuInfo);
    }

    @CallLuaFunction
    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        runFunc("onOptionsItemSelected", item);
        return super.onOptionsItemSelected(item);
    }

    @CallLuaFunction
    @Override
    public void onNightModeChanged(int i) {
        runFunc("onNightModeChanged", Integer.valueOf(i));
        super.onNightModeChanged(i);
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
        return mLuaDexLoader.getClassLoaders();
    }

    public DexClassLoader loadDex(String path) {
        return mLuaDexLoader.loadDex(path);
    }

    @Override
    public void call(String func, Object... args) {
        runOnUiThread(() -> globals.get(func).jcall(args));
    }

    @Override
    public void set(String name, Object value) {
        runOnUiThread(() -> globals.jset(name, value));
    }

    @Override
    public LuaValue __index(LuaValue key) {
        return globals.get(key);
    }

    @Override
    public void __newindex(LuaValue key, LuaValue value) {
        globals.set(key, value);
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

    public static ViewGroup getRootView(@NonNull Activity activity) {
        return (ViewGroup) activity.getWindow().getDecorView().getRootView();
    }

    @Override
    public Object doFile(String path, Object... arg) {
        return globals.loadfile(path).jcall(arg);
    }

    @Override
    public void sendMsg(final String msg) {
        runOnUiThread(
                () -> {
                    showToast(msg);
                    adapter.add(msg);
                    logs.add(msg);
                });
        Log.i("luaj", "sendMsg: " + msg);
    }

    @CallLuaFunction
    @Override
    public void sendError(String title, Exception msg) {
        Object run = runFunc("onError", title, msg);
        if (run == null || !(run instanceof Boolean)) {
            sendMsg(title + ": " + msg.getMessage());
            logs.add(title + ": " + msg.toString());
        }
    }

    public static void logError(String title, Exception msg) {
        if (sActivity != null) {
            sActivity.sendMsg(title + ": " + msg.getMessage());
        }
        logs.add(title + ": " + msg.toString());
    }

    @CallLuaFunction
    @Override
    protected void onStart() {
        super.onStart();
        sActivity = this;
        runFunc("onStart");
    }

    @CallLuaFunction
    @Override
    protected void onResume() {
        super.onResume();
        runFunc("onResume");
    }

    @CallLuaFunction
    @Override
    protected void onPause() {
        super.onPause();
        runFunc("onPause");
    }

    @CallLuaFunction
    @Override
    protected void onStop() {
        super.onStop();
        runFunc("onStop");
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

    @CallLuaFunction
    @Override
    public boolean onContextItemSelected(MenuItem menuItem) {
        runFunc("onContextItemSelected", menuItem);
        return super.onContextItemSelected(menuItem);
    }

    @CallLuaFunction
    @Override
    public void onContentChanged() {
        // TODO: Implement this method
        super.onContentChanged();
        runFunc("onContentChanged");
        isSetViewed = true;
    }

    public static LuaActivity getActivity(String name) {
        return sLuaActivityMap.get(name);
    }

    @CallLuaFunction
    @Override
    protected void onDestroy() {
        runFunc("onDestroy");
        for (LuaGcable g : mGc) {
            try {
                g.gc();
            } catch (Exception e) {

            }
        }
        mGc.clear();
        if (mReceiver != null) unregisterReceiver(mReceiver);
        sLuaActivityMap.remove(pageName);
        if (equals(sActivity)) sActivity = null;
        super.onDestroy();
    }

    @CallLuaFunction
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        // TODO: Implement this method
        if (data != null) {
            String name = data.getStringExtra(NAME);
            if (name != null) {
                Object[] res = (Object[]) data.getSerializableExtra(DATA);
                if (res == null) {
                    runFunc("onResult", name);
                } else {
                    Object[] arg = new Object[res.length + 1];
                    arg[0] = name;
                    for (int i = 0; i < res.length; i++) arg[i + 1] = res[i];
                    Object ret = runFunc("onResult", arg);
                    if (ret != null && ret.getClass() == Boolean.class && (Boolean) ret) return;
                }
            }
        }
        runFunc("onActivityResult", requestCode, resultCode, data);
        super.onActivityResult(requestCode, resultCode, data);
    }

    public void result(Object[] data) {
        Intent res = new Intent();
        res.putExtra(NAME, getIntent().getStringExtra(NAME));
        res.putExtra(DATA, data);
        setResult(0, res);
        finish();
    }

    @CallLuaFunction
    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        // TODO: Implement this method
        super.onConfigurationChanged(newConfig);
        runFunc("onConfigurationChanged", newConfig);
        initSize();
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

    @SuppressWarnings("unchecked")
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

    public boolean bindService(int flag) {
        ServiceConnection conn =
                new ServiceConnection() {

                    @CallLuaFunction
                    @Override
                    public void onServiceConnected(ComponentName comp, IBinder binder) {
                        // TODO: Implement this method
                        runFunc("onServiceConnected", comp, ((LuaService.LuaBinder) binder).getService());
                    }

                    @CallLuaFunction
                    @Override
                    public void onServiceDisconnected(ComponentName comp) {
                        // TODO: Implement this method
                        runFunc("onServiceDisconnected", comp);
                    }
                };
        return bindService(conn, flag);
    }

    public boolean bindService(ServiceConnection conn, int flag) {
        // TODO: Implement this method
        Intent service = new Intent(this, LuaService.class);
        String path = "service.lua";
        service.putExtra(NAME, path);
        if (path.charAt(0) != '/' && luaDir != null) path = luaDir + "/" + path;
        File f = new File(path);
        if (f.isDirectory() && new File(path + "/service.lua").exists()) path += "/service.lua";
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua";
        if (!new File(path).exists()) throw new LuaError(new FileNotFoundException(path));

        service.setData(Uri.parse("file://" + path));

        return super.bindService(service, conn, flag);
    }

    public boolean stopService() {
        return stopService(new Intent(this, LuaService.class));
    }

    public ComponentName startService() {
        return startService(null, null);
    }

    public ComponentName startService(Object[] arg) {
        return startService(null, arg);
    }

    public ComponentName startService(String path) {
        return startService(path, null);
    }

    public ComponentName startService(String path, Object[] arg) {
        // TODO: Implement this method
        Intent intent = new Intent(this, LuaService.class);
        intent.putExtra(NAME, path);
        if (path.charAt(0) != '/' && luaDir != null) path = luaDir + "/" + path;
        File f = new File(path);
        if (f.isDirectory() && new File(path + "/service.lua").exists()) path += "/service.lua";
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua";
        if (!new File(path).exists()) throw new LuaError(new FileNotFoundException(path));

        intent.setData(Uri.parse("file://" + path));

        if (arg != null) intent.putExtra(ARG, arg);

        if (arg != null) intent.putExtra(ARG, arg);

        return super.startService(intent);
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
        else startActivityForResult(intent, req);
        // overridePendingTransition(android.R.anim.slide_in_left, android.R.anim.slide_out_right);
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
        else startActivityForResult(intent, req);
        overridePendingTransition(in, out);
    }

    public void finish(boolean finishTask) {
        if (!finishTask) {
            super.finish();
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            Intent intent = getIntent();
            if (intent != null && (intent.getFlags() & Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0)
                finishAndRemoveTask();
            else super.finish();
        } else {
            super.finish();
        }
    }

    public Uri getUriForPath(String path) {
        return FileProvider.getUriForFile(this, getPackageName()+".fileprovider", new File(path));
    }

    public Uri getUriForFile(File path) {
        return FileProvider.getUriForFile(this, getPackageName()+"fileprovider", path);
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

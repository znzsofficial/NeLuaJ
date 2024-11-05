package com.androlua

import android.Manifest
import android.app.ActivityManager.TaskDescription
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.BlendMode
import android.graphics.BlendModeColorFilter
import android.graphics.ColorFilter
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.IBinder
import android.os.StrictMode
import android.os.StrictMode.ThreadPolicy
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.util.Log
import android.view.ContextMenu
import android.view.ContextMenu.ContextMenuInfo
import android.view.KeyEvent
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.MimeTypeMap
import android.widget.ImageView
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.view.ActionMode
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.util.TypedValueCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.preference.PreferenceManager
import coil.ImageLoader
import coil.request.ImageRequest
import com.androlua.LuaBroadcastReceiver.OnReceiveListener
import com.androlua.LuaService.LuaBinder
import com.androlua.adapter.ArrayListAdapter
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.nekolaska.ktx.toLuaInstance
import dalvik.system.DexClassLoader
import github.znzsofficial.neluaj.R
import kotlinx.coroutines.launch
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaFunction
import org.luaj.LuaMetaTable
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.android.AsyncOkHttp
import org.luaj.android.call
import org.luaj.android.file
import org.luaj.android.http
import org.luaj.android.json
import org.luaj.android.loadlayout
import org.luaj.android.okhttp
import org.luaj.android.print
import org.luaj.android.printf
import org.luaj.android.res
import org.luaj.android.task
import org.luaj.android.thread
import org.luaj.android.timer
import org.luaj.android.xTask
import org.luaj.lib.ResourceFinder
import org.luaj.lib.jse.JavaPackage
import org.luaj.lib.jse.JsePlatform
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.lang.Exception
import java.lang.StringBuilder
import java.util.ArrayList
import java.util.HashMap

open class LuaActivity : AppCompatActivity(), ResourceFinder, LuaContext, OnReceiveListener,
    LuaMetaTable {
    private lateinit var globals: Globals
    private val toastBuilder = StringBuilder()
    private var toast: Toast? = null
    private var lastShow: Long = 0
    private lateinit var adapter: ArrayListAdapter<String?>
    private var mExtDir: String? = null
    private var mWidth = 0
    private var mHeight = 0
    private var debug = false
    private var luaDir: String? = null
    private var luaFile = "main.lua"
    private var permissions: ArrayList<String?>? = null
    private var isSetViewed = false
    private lateinit var mLuaDexLoader: LuaDexLoader
    private val mGc = ArrayList<LuaGcable>()
    private var mReceiver: LuaBroadcastReceiver? = null
    private var pageName = "main"
    private var mOnKeyShortcut: LuaValue? = null
    private var mOnKeyDown: LuaValue? = null
    private var mOnKeyUp: LuaValue? = null
    private var mOnKeyLongPress: LuaValue? = null
    private var mOnTouchEvent: LuaValue? = null

    @CallLuaFunction
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val d = intent.data

        luaDir = filesDir.absolutePath
        if (d != null) {
            var p = d.path
            if (!p.isNullOrEmpty()) {
                val f = File(p)
                if (f.isFile()) {
                    p = f.getParent()
                    luaFile = f.absolutePath
                }
                luaDir = p
                setTitle(File(luaDir).getName())
            }
        }

        luaDir = checkProjectDir(File(luaDir)).absolutePath
        initSize()
        pageName = File(luaFile).getName()
        val idx = pageName.lastIndexOf(".")
        if (idx > 0) pageName = pageName.substring(0, idx)
        sLuaActivityMap.put(pageName, this)
        mLuaDexLoader = LuaDexLoader(this, luaDir)
        mLuaDexLoader.loadLibs()
        globals = JsePlatform.standardGlobals()
        // globals.finder = this;
        globals.m = this
        adapter = ArrayListAdapter<String?>(this, R.layout.item_log)
        initENV()

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
        globals.s.e = mLuaDexLoader.classLoaders
        sActivity = this
        try {
            globals.jset("activity", this)
            globals.jset("this", this)
            globals.set("print", print(this))
            globals.set("printf", printf(this))
            globals.set("loadlayout", loadlayout(this))
            globals.set("task", task(this))
            globals.set("thread", thread(this))
            globals.set("timer", timer(this))
            globals.set("call", call(this))
            globals.set("xTask", xTask(this))
            globals.set("okHttp", AsyncOkHttp(this).toLuaInstance())
            globals.load(res(this))
            globals.load(json())
            globals.load(file())
            globals.load(okhttp())
            globals.jset("Http", Http::class.java)
            globals.jset("http", http::class.java)
            globals.jset("R", R::class.java)
            globals.set("android", JavaPackage("android"))
            var arg = intent.getSerializableExtra(ARG) as Array<*>?
            if (arg == null) arg = arrayOfNulls<Any>(0)
            doFile(luaFile, arg)
            runMainFunc(pageName, arg)
            runFunc("onCreate")
            if (!isSetViewed) showLogView(false)
            globals.get("onKeyShortcut").apply {
                mOnKeyShortcut = if (isnil()) null
                else this
            }
            globals.get("onKeyDown").apply {
                mOnKeyDown = if (isnil()) null
                else this
            }
            globals.get("onKeyUp").apply {
                mOnKeyUp = if (isnil()) null
                else this
            }
            globals.get("onKeyLongPress").apply {
                mOnKeyLongPress = if (isnil()) null
                else this
            }
            globals.get("onTouchEvent").apply {
                mOnTouchEvent = if (isnil()) null
                else this
            }
            if (intent.getBooleanExtra(
                    "isVersionChanged",
                    false
                ) && (savedInstanceState == null)
            ) {
                runFunc(
                    "onVersionChanged",
                    intent.getStringExtra("newVersionName"),
                    intent.getStringExtra("oldVersionName")
                )
            }
        } catch (e: Exception) {
            sendError("Error", e)
            showLogView(true)
            val res = Intent()
            res.putExtra(DATA, e.toString())
            setResult(-1, res)
        }
    }

    private fun showLogView(isError: Boolean) {
        setTheme(com.google.android.material.R.style.Theme_Material3_DynamicColors_DayNight)
        if (isError) setTitle("Runtime Error")
        else setTitle("Log")
        supportActionBar?.elevation = 0f
        setContentView(R.layout.log_view)
        (findViewById<View?>(R.id.file_name) as TextView).text = File(luaFile).getName()
        val list = findViewById<ListView>(R.id.log_list)
        list.setAdapter(adapter)
        findViewById<View?>(R.id.clear).setOnClickListener { v: View? -> adapter.clear() }
        findViewById<View?>(R.id.copy).setOnClickListener { v: View? ->
            // 合并所有字符串
            val combinedString = StringBuilder()
            for (i in 0 until adapter.count) {
                combinedString.append(adapter.getItem(i))
                if (i < adapter.count - 1) {
                    combinedString.append("\n") // 添加分隔
                }
            }
            val clipboard = ContextCompat.getSystemService<ClipboardManager?>(
                this,
                ClipboardManager::class.java
            )
            // 创建 ClipData 对象
            val clip = ClipData.newPlainText("log", combinedString)
            // 将数据设置到剪贴板
            clipboard?.setPrimaryClip(clip)
        }
    }

    fun setAllowThread(bool: Boolean) {
        var policy = if (bool) {
            ThreadPolicy.Builder().permitAll().build()
        } else {
            ThreadPolicy.Builder().detectAll().build()
        }
        StrictMode.setThreadPolicy(policy)
    }

    fun runMainFunc(name: String?, vararg arg: Any): Any? {
        try {
            var f = globals.get(name)
            if (f.isfunction()) return f.jcall(arg)
            f = globals.get("main")
            if (f.isfunction()) return f.jcall(arg)
        } catch (e: Exception) {
            sendError(name, e)
        }
        return null
    }

    @CallLuaFunction
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        runFunc("onRequestPermissionsResult", requestCode, permissions, grantResults)
    }

    @CallLuaFunction
    override fun onKeyShortcut(keyCode: Int, event: KeyEvent?): Boolean {
        if (mOnKeyShortcut != null) {
            try {
                val ret = mOnKeyShortcut!!.jcall(keyCode, event)
                if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return true
            } catch (e: LuaError) {
                sendError("onKeyShortcut", e)
            }
        }
        return super.onKeyShortcut(keyCode, event)
    }

    @CallLuaFunction
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (mOnKeyDown != null) {
            try {
                val ret = mOnKeyDown!!.jcall(keyCode, event)
                if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return true
            } catch (e: LuaError) {
                sendError("onKeyDown", e)
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    @CallLuaFunction
    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (mOnKeyUp != null) {
            try {
                val ret = mOnKeyUp!!.jcall(keyCode, event)
                if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return true
            } catch (e: LuaError) {
                sendError("onKeyUp", e)
            }
        }
        return super.onKeyUp(keyCode, event)
    }

    @CallLuaFunction
    override fun onKeyLongPress(keyCode: Int, event: KeyEvent?): Boolean {
        if (mOnKeyLongPress != null) {
            try {
                val ret = mOnKeyLongPress!!.jcall(keyCode, event)
                if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return true
            } catch (e: LuaError) {
                sendError("onKeyLongPress", e)
            }
        }
        return super.onKeyLongPress(keyCode, event)
    }

    @CallLuaFunction
    override fun onTouchEvent(event: MotionEvent?): Boolean {
        if (mOnTouchEvent != null) {
            try {
                val ret = mOnTouchEvent!!.jcall(event)
                if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return true
            } catch (e: LuaError) {
                sendError("onTouchEvent", e)
            }
        }
        return super.onTouchEvent(event)
    }

    private fun checkProjectDir(dir: File?): File {
        if (dir == null) return File(luaDir)
        if (File(dir, "main.lua").exists() && File(dir, "init.lua").exists()) return dir
        return checkProjectDir(dir.getParentFile())
    }

    protected fun initENV() {
        if (!File("$luaDir/init.lua").exists()) return
        try {
            val env = LuaTable()
            globals.loadfile("init.lua", env).call()
            var title = env.get("appname")
            if (title.isstring()) setTitle(title.tojstring())
            title = env.get("app_name")
            if (title.isstring()) setTitle(title.tojstring())
            var debug = env.get("debugmode")
            if (debug.isboolean()) setDebug(debug.toboolean())
            debug = env.get("debug_mode")
            if (debug.isboolean()) setDebug(debug.toboolean())
            val theme = env.get("theme")
            if (theme.isint()) setTheme(theme.toint())
            else if (theme.isstring()) setTheme(
                android.R.style::class.java.getField(theme.tojstring()).getInt(null)
            )
            val myTheme = env.get("NeLuaJ_Theme")
            if (myTheme.isstring()) setTheme(
                R.style::class.java.getField(myTheme.tojstring()).getInt(null)
            )
        } catch (e: Exception) {
            sendMsg(e.message)
        }
    }

    override fun setTitle(title: CharSequence) {
        super.setTitle(title)
        val tDesc = TaskDescription(title.toString())
        setTaskDescription(tDesc)
    }

    fun setContentView(view: LuaTable) {
        isSetViewed = true
        setContentView(LuaLayout(this).load(view, globals).touserdata<View?>(View::class.java))
    }

    fun setContentView(view: LuaTable, env: LuaTable) {
        isSetViewed = true
        setContentView(LuaLayout(this).load(view, env).touserdata<View?>(View::class.java))
    }

    fun setFragment(fragment: Fragment) {
        isSetViewed = true
        setContentView(View(this))
        supportFragmentManager.beginTransaction().replace(android.R.id.content, fragment)
            .commit()
    }

    fun showLogs() {
        MaterialAlertDialogBuilder(this)
            .setTitle("Logs")
            .setAdapter(adapter, null)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    fun setDebug(bool: Boolean) {
        debug = bool
    }

    private fun initSize() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val outMetrics = DisplayMetrics()
        wm.defaultDisplay.getMetrics(outMetrics)
        mWidth = outMetrics.widthPixels
        mHeight = outMetrics.heightPixels
    }

    fun checkAllPermissions(): Boolean {
        if (checkCallingOrSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            try {
                permissions = ArrayList<String?>()
                val pm = packageManager
                val ps2 =
                    pm.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
                        .requestedPermissions
                for (p in ps2) {
                    try {
                        if ((pm.getPermissionInfo(
                                p,
                                0
                            ).protectionLevel and 1) != 0
                        ) checkPermission(p)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
                if (!permissions!!.isEmpty) {
                    val ps = arrayOfNulls<String>(permissions!!.size)
                    permissions!!.toArray<String?>(ps)
                    requestPermissions(ps, 0)
                    return false
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return true
    }

    private fun checkPermission(permission: String?) {
        if (checkCallingOrSelfPermission(permission!!) != PackageManager.PERMISSION_GRANTED) {
            permissions!!.add(permission)
        }
    }

    @CallLuaFunction
    override fun onCreateOptionsMenu(menu: Menu?): Boolean {
        runFunc("onCreateOptionsMenu", menu)
        return true
    }

    @CallLuaFunction
    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        runFunc("onOptionsItemSelected", item)
        return super.onOptionsItemSelected(item)
    }

    @CallLuaFunction
    override fun onCreateContextMenu(
        contextMenu: ContextMenu?, view: View?, contextMenuInfo: ContextMenuInfo?
    ) {
        runFunc("onCreateContextMenu", contextMenu, view, contextMenuInfo)
        super.onCreateContextMenu(contextMenu, view, contextMenuInfo)
    }

    @CallLuaFunction
    override fun onContextItemSelected(menuItem: MenuItem): Boolean {
        runFunc("onContextItemSelected", menuItem)
        return super.onContextItemSelected(menuItem)
    }


    @CallLuaFunction
    public override fun onNightModeChanged(i: Int) {
        runFunc("onNightModeChanged", i)
        super.onNightModeChanged(i)
    }

    @CallLuaFunction
    override fun onPanelClosed(featureId: Int, menu: Menu) {
        runFunc("onPanelClosed", featureId, menu)
        super.onPanelClosed(featureId, menu)
    }

    @CallLuaFunction
    override fun onSupportActionModeStarted(mode: ActionMode) {
        runFunc("onSupportActionModeStarted", mode)
        super.onSupportActionModeStarted(mode)
    }

    @CallLuaFunction
    override fun onSupportActionModeFinished(mode: ActionMode) {
        runFunc("onSupportActionModeFinished", mode)
        super.onSupportActionModeFinished(mode)
    }

    fun runFunc(name: String?, vararg arg: Any?): Any? {
        try {
            val func = globals.get(name)
            if (func.isfunction()) return func.jcall(*arg)
        } catch (e: Exception) {
            sendError(name, e)
        }
        return null
    }

    override fun findResource(name: String): InputStream? {
        try {
            val file = File(name)
            if (file.exists()) return FileInputStream(file)
        } catch (_: Exception) {
        }
        try {
            return FileInputStream(getLuaPath(name))
        } catch (_: Exception) {
        }
        try {
            return assets.open(name)
        } catch (_: Exception) {
        }
        return null
    }

    fun checkResource(name: String): Boolean {
        try {
            if (File(name).exists()) return true
        } catch (_: Exception) {
        }
        try {
            return File(getLuaPath(name)).exists()
        } catch (_: Exception) {
        }
        try {
            val stream = assets.open(name)
            stream.close()
            return true
        } catch (_: Exception) {
        }
        return false
    }

    override fun findFile(filename: String): String {
        if (filename.startsWith("/")) return filename
        return getLuaPath(filename)
    }

    fun showToast(text: String?) {
        if (!debug) return
        val now = System.currentTimeMillis()
        if (toast == null || now - lastShow > 1000) {
            toastBuilder.setLength(0)
            toast = Toast.makeText(this, text, Toast.LENGTH_LONG)
            toastBuilder.append(text)
            toast!!.show()
        } else {
            toastBuilder.append("\n")
            toastBuilder.append(text)
            toast!!.setText(toastBuilder.toString())
            toast!!.setDuration(Toast.LENGTH_LONG)
        }
        lastShow = now
    }

    override fun getClassLoaders(): ArrayList<ClassLoader?>? {
        return mLuaDexLoader.classLoaders
    }

    fun loadDex(path: String?): DexClassLoader? {
        return mLuaDexLoader.loadDex(path)
    }

    override fun call(func: String?, vararg args: Any?) {
        runOnUiThread { globals.get(func).jcall(*args) }
    }

    override fun set(name: String?, value: Any?) {
        runOnUiThread { globals.jset(name, value) }
    }

    override fun __index(key: LuaValue?): LuaValue? {
        return globals.get(key)
    }

    override fun __newindex(key: LuaValue?, value: LuaValue?) {
        globals.set(key, value)
    }

    override fun getLuaPath(): String {
        return luaFile
    }

    override fun getLuaPath(path: String): String {
        return File(luaDir, path).absolutePath
    }

    override fun getLuaPath(dir: String, name: String): String {
        return File(getLuaDir(dir), name).absolutePath
    }

    override fun getLuaDir(): String? {
        return luaDir
    }

    override fun getLuaDir(dir: String): String {
        return File(luaDir, dir).absolutePath
    }

    override fun getLuaExtDir(): String {
        if (mExtDir != null) return mExtDir!!
        val d = File(Environment.getExternalStorageDirectory(), "LuaJ")
        if (!d.exists()) d.mkdirs()
        mExtDir = d.absolutePath
        return mExtDir!!
    }

    override fun getLuaExtDir(dir: String): String {
        val d = File(getLuaExtDir(), dir)
        if (!d.exists()) d.mkdirs()
        return d.absolutePath
    }

    override fun setLuaExtDir(dir: String?) {
        mExtDir = dir
    }

    override fun getLuaExtPath(path: String): String {
        return File(getLuaExtDir(), path).absolutePath
    }

    override fun getLuaExtPath(dir: String, name: String): String {
        return File(getLuaExtDir(dir), name).absolutePath
    }

    override fun getContext(): Context {
        return this
    }

    override fun getLuaState(): Globals {
        return globals
    }

    fun getDecorView(): ViewGroup {
        return window.decorView as ViewGroup
    }

    fun getRootView(): ViewGroup? {
        return window.decorView.rootView as ViewGroup?
    }

    override fun doFile(path: String?, vararg arg: Any?): Any? {
        return globals.loadfile(path).jcall(*arg)
    }

    override fun sendMsg(msg: String?) {
        runOnUiThread {
            showToast(msg)
            adapter.add(msg)
            logs.add(msg)
        }
        Log.i("luaj", "sendMsg: $msg")
    }

    @CallLuaFunction
    override fun sendError(title: String?, exception: Exception) {
        val ret = runFunc("onError", title, exception)
        if (ret == null) {
            sendMsg(title + ": " + exception.message)
            return
        }
        when (ret.toString()) {
            "trace" -> sendMsg(
                title + ": " + exception.message + "\n" + exception.stackTraceToString()
            )

            "log" -> sendMsg(title + ": " + exception.message)
            "message" -> sendMsg(exception.message)
            "title" -> sendMsg(title)
        }
    }

    @CallLuaFunction
    override fun onStart() {
        super.onStart()
        sActivity = this
        runFunc("onStart")
    }

    @CallLuaFunction
    override fun onResume() {
        super.onResume()
        runFunc("onResume")
    }

    @CallLuaFunction
    override fun onPause() {
        super.onPause()
        runFunc("onPause")
    }

    @CallLuaFunction
    override fun onStop() {
        super.onStop()
        runFunc("onStop")
    }

    fun registerReceiver(receiver: LuaBroadcastReceiver?, filter: IntentFilter?): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) super.registerReceiver(
            receiver,
            filter,
            RECEIVER_NOT_EXPORTED
        )
        else super.registerReceiver(receiver, filter)
    }

    fun registerReceiver(ltr: OnReceiveListener?, filter: IntentFilter?): Intent? {
        val receiver = LuaBroadcastReceiver(ltr)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) super.registerReceiver(
            receiver,
            filter,
            RECEIVER_NOT_EXPORTED
        )
        else super.registerReceiver(receiver, filter)
    }

    fun registerReceiver(filter: IntentFilter?): Intent? {
        if (mReceiver != null) unregisterReceiver(mReceiver)
        mReceiver = LuaBroadcastReceiver(this)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) super.registerReceiver(
            mReceiver,
            filter,
            RECEIVER_NOT_EXPORTED
        )
        else super.registerReceiver(mReceiver, filter)
    }

    override fun unregisterReceiver(receiver: BroadcastReceiver?) {
        try {
            super.unregisterReceiver(receiver)
        } catch (e: Exception) {
            Log.i("lua", "unregisterReceiver: $receiver")
            e.printStackTrace()
        }
    }

    @CallLuaFunction
    override fun onReceive(context: Context?, intent: Intent?) {
        runFunc("onReceive", context, intent)
    }


    @CallLuaFunction
    override fun onContentChanged() {
        super.onContentChanged()
        runFunc("onContentChanged")
        isSetViewed = true
    }

    @CallLuaFunction
    override fun onDestroy() {
        runFunc("onDestroy")
        mGc.forEach {
            runCatching { it.gc() }
        }
        mGc.clear()
        if (mReceiver != null) unregisterReceiver(mReceiver)
        sLuaActivityMap.remove(pageName)
        if (equals(sActivity)) sActivity = null
        super.onDestroy()
    }

    @CallLuaFunction
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (data != null) {
            val name = data.getStringExtra(NAME)
            if (name != null) {
                val res = data.getSerializableExtra(DATA) as Array<Any?>?
                if (res == null) {
                    runFunc("onResult", name)
                } else {
                    val arg = arrayOfNulls<Any>(res.size + 1)
                    arg[0] = name
                    System.arraycopy(res, 0, arg, 1, res.size)
                    val ret = runFunc("onResult", *arg)
                    if (ret != null && ret.javaClass == Boolean::class.java && ret as Boolean) return
                }
            }
        }
        runFunc("onActivityResult", requestCode, resultCode, data)
        super.onActivityResult(requestCode, resultCode, data)
    }

    fun result(data: Array<Any?>?) {
        val res = Intent()
        res.putExtra(NAME, intent.getStringExtra(NAME))
        res.putExtra(DATA, data)
        setResult(0, res)
        finish()
    }

    @CallLuaFunction
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        runFunc("onConfigurationChanged", newConfig)
        initSize()
    }

    override fun getWidth(): Int {
        return mWidth
    }

    override fun getHeight(): Int {
        return mHeight
    }

    override fun getGlobalData(): Map<*, *> {
        return LuaApplication.instance.globalData
    }

    override fun getSharedData(): MutableMap<String?, *>? {
        return PreferenceManager.getDefaultSharedPreferences(this).all
    }

    override fun getSharedData(key: String?): Any? {
        return PreferenceManager.getDefaultSharedPreferences(this).all[key]
    }

    override fun getSharedData(key: String?, def: Any?): Any? {
        val ret: Any? = PreferenceManager.getDefaultSharedPreferences(this).all[key]
        if (ret != null) return ret
        return def
    }

    override fun setSharedData(key: String?, value: Any?): Boolean {
        val edit = PreferenceManager.getDefaultSharedPreferences(this).edit()
        if (value == null) edit.remove(key)
        else if (value is String) edit.putString(key, value.toString())
        else if (value is Long) edit.putLong(key, value)
        else if (value is Int) edit.putInt(key, value)
        else if (value is Float) edit.putFloat(key, value)
        else if (value is LuaTable) edit.putStringSet(
            key,
            value.values().toSet() as MutableSet<String?>
        )
        else if (value is MutableSet<*>) edit.putStringSet(key, value as MutableSet<String?>)
        else if (value is Boolean) edit.putBoolean(key, value)
        else return false
        return edit.commit()
    }

    override fun regGc(obj: LuaGcable?) {
        mGc.add(obj!!)
    }

    fun bindService(flag: Int): Boolean {
        val conn: ServiceConnection =
            object : ServiceConnection {
                @CallLuaFunction
                override fun onServiceConnected(comp: ComponentName?, binder: IBinder) {
                    runFunc("onServiceConnected", comp, (binder as LuaBinder).service)
                }

                @CallLuaFunction
                override fun onServiceDisconnected(comp: ComponentName?) {
                    runFunc("onServiceDisconnected", comp)
                }
            }
        return bindService(conn, flag)
    }

    fun bindService(conn: ServiceConnection, flag: Int): Boolean {
        val service = Intent(this, LuaService::class.java)
        var path = "service.lua"
        service.putExtra(NAME, path)
        if (luaDir != null) path = "$luaDir/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/service.lua").exists()) path += "/service.lua"
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua"
        if (!File(path).exists()) throw LuaError(FileNotFoundException(path))

        service.setData(Uri.parse("file://$path"))

        return super.bindService(service, conn, flag)
    }

    fun stopService(): Boolean {
        return stopService(Intent(this, LuaService::class.java))
    }

    fun startService(): ComponentName? {
        return startService(null, null)
    }

    fun startService(arg: Array<Any?>?): ComponentName? {
        return startService(null, arg)
    }

    fun startService(path: String): ComponentName? {
        return startService(path, null)
    }

    fun startService(path: String?, arg: Array<Any?>?): ComponentName? {
        var path = path
        val intent = Intent(this, LuaService::class.java)
        intent.putExtra(NAME, path)
        if (path?.get(0) != '/' && luaDir != null) path = "$luaDir/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/service.lua").exists()) path += "/service.lua"
        else if ((f.isDirectory() || !f.exists()) && !path?.endsWith(".lua")!!) path += ".lua"
        if (!File(path).exists()) throw LuaError(FileNotFoundException(path))

        intent.setData(Uri.parse("file://$path"))

        if (arg != null) intent.putExtra(ARG, arg)

        if (arg != null) intent.putExtra(ARG, arg)

        return super.startService(intent)
    }

    /**
     * 新建活动
     *
     * @param path        文件路径
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, newDocument: Boolean) {
        newActivity(1, path, null, newDocument)
    }

    /**
     * 新建活动
     *
     * @param path        文件路径
     * @param arg         参数数组
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, arg: Array<Any?>?, newDocument: Boolean) {
        newActivity(1, path, arg, newDocument)
    }

    /**
     * 新建活动
     *
     * @param req         请求码
     * @param path        文件路径
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, newDocument: Boolean) {
        newActivity(req, path, null, newDocument)
    }

    /**
     * 新建活动
     *
     * @param path 文件路径
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String) {
        newActivity(1, path, arrayOfNulls<Any>(0))
    }

    /**
     * 新建活动
     *
     * @param path 文件路径
     * @param arg  参数数组
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, arg: Array<Any?>?) {
        newActivity(1, path, arg)
    }

    /**
     * 新建活动
     *
     * @param req  请求码
     * @param path 文件路径
     * @param arg  参数数组
     * @throws FileNotFoundException 文件未找到异常
     */
    @JvmOverloads
    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, arg: Array<Any?>? = arrayOfNulls<Any>(0)) {
        newActivity(req, path, arg, false)
    }

    /**
     * 新建活动
     *
     * @param req         请求码
     * @param path        文件路径
     * @param arg         参数数组
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, arg: Array<Any?>?, newDocument: Boolean) {
        // Log.i("luaj", "newActivity: "+path+ Arrays.toString(arg));
        var path = path
        var intent = Intent(this, LuaActivity::class.java)
        if (newDocument) intent = Intent(this, LuaActivityX::class.java)

        intent.putExtra(NAME, path)
        if (path[0] != '/' && luaDir != null) path = "$luaDir/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/main.lua").exists()) path += "/main.lua"
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua"
        if (!File(path).exists()) throw FileNotFoundException(path)

        if (newDocument) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        intent.setData(Uri.parse("file://$path"))

        if (arg != null) intent.putExtra(ARG, arg)
        if (newDocument) startActivity(intent)
        else startActivityForResult(intent, req)
        // overridePendingTransition(android.R.anim.slide_in_left, android.R.anim.slide_out_right);
    }

    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, newDocument: Boolean) {
        newActivity(1, path, `in`, out, null, newDocument)
    }

    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, arg: Array<Any?>?, newDocument: Boolean) {
        newActivity(1, path, `in`, out, arg, newDocument)
    }

    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, `in`: Int, out: Int, newDocument: Boolean) {
        newActivity(req, path, `in`, out, null, newDocument)
    }

    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int) {
        newActivity(1, path, `in`, out, arrayOfNulls<Any>(0))
    }

    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, arg: Array<Any?>?) {
        newActivity(1, path, `in`, out, arg)
    }

    @JvmOverloads
    @Throws(FileNotFoundException::class)
    fun newActivity(
        req: Int,
        path: String,
        `in`: Int,
        out: Int,
        arg: Array<Any?>? = arrayOfNulls<Any>(0)
    ) {
        newActivity(req, path, `in`, out, arg, false)
    }

    /**
     * 创建一个新的活动
     *
     * @param req         请求码
     * @param path        活动的路径
     * @param in          进入动画资源
     * @param out         出去动画资源
     * @param arg         活动的参数
     * @param newDocument 是否创建新的文档
     * @throws FileNotFoundException 如果文件不存在
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(
        req: Int,
        path: String,
        `in`: Int,
        out: Int,
        arg: Array<Any?>?,
        newDocument: Boolean
    ) {
        var path = path
        var intent = Intent(this, LuaActivity::class.java)
        if (newDocument) intent = Intent(this, LuaActivityX::class.java)
        intent.putExtra(NAME, path)
        if (path[0] != '/' && luaDir != null) path = "$luaDir/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/main.lua").exists()) path += "/main.lua"
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua"
        if (!File(path).exists()) throw FileNotFoundException(path)

        intent.setData(Uri.parse("file://$path"))

        if (newDocument) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        if (arg != null) intent.putExtra(ARG, arg)
        if (newDocument) startActivity(intent)
        else startActivityForResult(intent, req)
        overridePendingTransition(`in`, out)
    }

    /**
     * 结束活动
     *
     * @param finishTask 是否结束任务
     */
    fun finish(finishTask: Boolean) {
        if (!finishTask) {
            super.finish()
            return
        }
        val intent = getIntent()
        if (intent != null && (intent.flags and Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0) finishAndRemoveTask()
        else super.finish()
    }

    fun getUriForPath(path: String): Uri? {
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
    }

    fun getUriForFile(path: File): Uri? {
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", path)
    }

    fun getPathFromUri(uri: Uri?): String? {
        var path: String? = null
        uri?.let {
            val p = arrayOf(MediaStore.Images.Media.DATA)
            when (it.scheme) {
                "content" -> {
                    val cursor = contentResolver.query(it, p, null, null, null)
                    cursor?.use {
                        val idx = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                        if (idx >= 0) {
                            it.moveToFirst()
                            path = it.getString(idx)
                        }
                    }
                }

                "file" -> {
                    path = it.path
                }
            }
        }
        return path
    }

    private fun getType(file: File): String {
        val lastDot = file.getName().lastIndexOf(46.toChar())
        if (lastDot >= 0) {
            val extension = file.getName().substring(lastDot + 1)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            if (mime != null) {
                return mime
            }
        }
        return "application/octet-stream"
    }

    fun openFile(path: String) {
        openFile(path, null)
    }

    fun openFile(path: String, callback: LuaFunction?) {
        val file = File(path)
        // 创建Intent并设置相关标志和类型
        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK
            setDataAndType(getUriForFile(file), getType(file))
        }
        startActivity(intent)
        if (callback != null) {
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            } else {
                callback.call()
            }
        } else startActivity(intent)
    }

    fun startPackage(pkg: String) {
        val intent = packageManager.getLaunchIntentForPackage(pkg)
        if (intent != null) startActivity(intent)
        else Toast.makeText(this, "未找到应用", Toast.LENGTH_SHORT).show()
    }

    fun installApk(path: String) {
        val share = Intent(Intent.ACTION_VIEW)
        val file = File(path)
        share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        share.setDataAndType(getUriForFile(file), getType(file))
        share.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(share)
    }

    fun shareFile(path: String) {
        val share = Intent(Intent.ACTION_SEND)
        val file = File(path)
        share.setType("*/*")
        share.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        share.putExtra(Intent.EXTRA_STREAM, getUriForFile(file))
        startActivity(
            Intent.createChooser(share, file.getName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    fun isNightMode() =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES


    fun getFilter(color: Int): ColorFilter {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            BlendModeColorFilter(color, BlendMode.SRC_ATOP)
        } else {
            PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP)
        }
    }

    fun getResDrawable(name: String?): Drawable {
        val path = "$luaDir/res/drawable/$name.png"
        return BitmapDrawable(resources, BitmapFactory.decodeFile(path))
    }

    fun getResDrawable(name: String?, color: Int): Drawable {
        val path = "$luaDir/res/drawable/$name.png"
        val drawable = BitmapDrawable(resources, BitmapFactory.decodeFile(path))
        drawable.colorFilter = getFilter(color)
        return drawable
    }

    fun getImageLoader(): ImageLoader {
        return LuaApplication.loader
    }

    fun loadImage(data: Any?, callback: LuaFunction) =
        LuaApplication.loader.enqueue(
            ImageRequest.Builder(this)
                .data(data)
                .target(SimpleTarget(callback))
                .build()
        )


    fun loadImage(data: Any?, view: ImageView) =
        LuaApplication.loader.enqueue(
            ImageRequest.Builder(this)
                .data(data)
                .target(view)
                .build()
        )

    fun dpToPx(dp: Float): Float {
        return TypedValueCompat.dpToPx(dp, resources.displayMetrics)
    }

    fun addOnBackPressedCallback(callback: LuaFunction) {
        onBackPressedDispatcher.addCallback(LuaBackPressedCallback(callback))
    }

    fun delay(time: Long, callback: LuaFunction) = lifecycleScope.launch {
        kotlinx.coroutines.delay(time)
        callback.call()
    }

    fun getMediaDir() = externalMediaDirs[0]

    companion object {
        private const val ARG = "arg"
        private const val DATA = "data"
        private const val NAME = "name"

        @JvmField
        var logs = ArrayList<String?>()

        @JvmField
        var sActivity: LuaActivity? = null
        private val sLuaActivityMap = HashMap<String?, LuaActivity?>()

        @JvmStatic
        fun logError(title: String?, msg: Exception) {
            sActivity?.sendMsg(title + ": " + msg.message)
            logs.add("$title: $msg")
        }

        @JvmStatic
        fun getActivity(name: String?): LuaActivity? {
            return sLuaActivityMap[name]
        }
    }
}

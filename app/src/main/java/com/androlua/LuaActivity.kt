package com.androlua

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager.TaskDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.content.res.Configuration
import android.content.res.XmlResourceParser
import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.BlendModeColorFilter
import android.graphics.ColorFilter
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.IBinder
import android.os.StrictMode
import android.os.StrictMode.ThreadPolicy
import android.provider.MediaStore
import android.provider.Settings
import android.view.ContextMenu
import android.view.ContextMenu.ContextMenuInfo
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.MimeTypeMap
import android.widget.ImageView
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.view.ActionMode
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import androidx.core.util.TypedValueCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.preference.PreferenceManager
import androidx.window.layout.WindowMetricsCalculator
import coil3.ImageLoader
import coil3.asDrawable
import coil3.executeBlocking
import coil3.imageLoader
import coil3.load
import coil3.request.ImageRequest
import coil3.request.crossfade
import coil3.toBitmap
import com.androlua.LuaBroadcastReceiver.OnReceiveListener
import com.androlua.LuaService.LuaBinder
import com.androlua.adapter.ArrayListAdapter
import com.google.android.material.color.DynamicColors
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.nekolaska.internal.commit
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.overridePendingTransition
import com.nekolaska.ktx.toLuaInstance
import dalvik.system.DexClassLoader
import github.daisukiKaffuChino.utils.LuaThemeUtil
import github.znzsofficial.neluaj.R
import kotlinx.coroutines.launch
import org.luaj.Globals
import org.luaj.LuaClosure
import org.luaj.LuaError
import org.luaj.LuaFunction
import org.luaj.LuaMetaTable
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
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
import org.luaj.android.thread as luajthread
import org.luaj.android.timer
import org.luaj.android.xTask
import org.luaj.compiler.DumpState
import org.luaj.lib.ResourceFinder
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.JavaPackage
import org.luaj.lib.jse.JsePlatform
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import kotlin.system.measureTimeMillis

@Suppress("UNUSED")
open class LuaActivity : AppCompatActivity(), ResourceFinder, LuaContext, OnReceiveListener,
    LuaMetaTable {
    private lateinit var globals: Globals
    private val toastBuilder = StringBuilder()
    private var toast: Toast? = null
    private var lastShow: Long = 0
    private lateinit var logAdapter: LogAdapter
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
    val themeUtil = LuaThemeUtil(this)

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    @CallLuaFunction
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        luaDir = filesDir.absolutePath
        intent.data?.let {
            var p = it.path
            if (!p.isNullOrEmpty()) {
                val f = File(p)
                if (f.isFile()) {
                    p = f.getParent()
                    luaFile = f.absolutePath
                }
                luaDir = p
                setTitle(File(luaDir!!).getName())
            }
        }
        luaDir = checkProjectDir(File(luaDir!!)).absolutePath
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
        logAdapter = LogAdapter(this)
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
            globals.let {
                it.jset("activity", this)
                it.jset("this", this)
                it.set("print", print(this))
                it.set("printf", printf(this))
                it.set("loadlayout", loadlayout(this))
                it.set("task", task(this))
                it.set("thread", luajthread(this))
                it.set("timer", timer(this))
                it.set("call", call(this))
                it.set("xTask", xTask(this))
                it.set("okHttp", AsyncOkHttp(this).toLuaInstance())
                it.set("lazy", object : VarArgFunction() {
                    override fun invoke(args: Varargs) = lazy {
                        args.firstArg().invoke(args.subargs(2))
                    }.toLuaInstance()
                })
                it.load(res(this))
                it.load(json())
                it.load(file())
                it.load(okhttp())
                it.jset("Http", Http::class.java)
                it.jset("http", http)
                it.jset("R", R::class.java)
                it.set("android", JavaPackage("android"))
                var arg = intent.getSerializableExtra(ARG) as Array<Any?>?
                if (arg == null) arg = arrayOfNulls(0)
                doFile(luaFile, *arg)
                //runMainFunc(pageName, *arg)
                runFunc("onCreate")
                if (!isSetViewed) showLogView(false)
                it.get("onKeyShortcut").apply {
                    mOnKeyShortcut = if (isnil()) null
                    else this
                }
                it.get("onKeyDown").apply {
                    mOnKeyDown = if (isnil()) null
                    else this
                }
                it.get("onKeyUp").apply {
                    mOnKeyUp = if (isnil()) null
                    else this
                }
                it.get("onKeyLongPress").apply {
                    mOnKeyLongPress = if (isnil()) null
                    else this
                }
                it.get("onTouchEvent").apply {
                    mOnTouchEvent = if (isnil()) null
                    else this
                }
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
        setContentView(R.layout.log_list)
        findViewById<TextView>(R.id.file_name).text = File(luaFile).name

        val logListView = findViewById<ListView>(R.id.log_list)
        logListView.adapter = logAdapter

        findViewById<View>(R.id.clear).setOnClickListener {
            // 清理时也需要操作新的adapter
            logAdapter.clear()
            logAdapter.notifyDataSetChanged()
        }
        findViewById<View>(R.id.copy).setOnClickListener {
            val clipboard = ContextCompat.getSystemService(
                this,
                ClipboardManager::class.java
            )
            val clip = ClipData.newPlainText("log", buildString {
                for (i in 0 until logAdapter.count) {
                    append(logAdapter.getItem(i))
                    if (i < logAdapter.count - 1) {
                        append("\n")
                    }
                }
            })
            clipboard?.setPrimaryClip(clip)
        }
    }

    fun setAllowThread(bool: Boolean) {
        val policy = if (bool) {
            ThreadPolicy.Builder().permitAll().build()
        } else {
            ThreadPolicy.Builder().detectAll().build()
        }
        StrictMode.setThreadPolicy(policy)
    }

//    fun runMainFunc(name: String?, vararg arg: Any?): Any? {
//        try {
//            var f = globals.get(name)
//            if (f.isfunction()) return f.jcall(*arg)
//            f = globals.get("main")
//            if (f.isfunction()) return f.jcall(*arg)
//        } catch (e: Exception) {
//            sendError(name, e)
//        }
//        return null
//    }
//    fun runMainFunc(name: String?, arg: Array<Any?>): Any? {
//        try {
//            var f = globals.get(name)
//            if (f.isfunction()) return f.jcall(*arg)
//            f = globals.get("main")
//            if (f.isfunction()) return f.jcall(*arg)
//        } catch (e: Exception) {
//            sendError(name, e)
//        }
//        return null
//    }

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
                if (ret != null && ret as Boolean) return ret
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
                if (ret != null && ret as Boolean) return ret
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
                if (ret != null && ret as Boolean) return ret
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
                if (ret != null && ret as Boolean) return ret
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
                if (ret != null && ret as Boolean) return ret
            } catch (e: LuaError) {
                sendError("onTouchEvent", e)
            }
        }
        return super.onTouchEvent(event)
    }

    private fun checkProjectDir(dir: File?): File {
        if (dir == null) return File(luaDir!!)
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

    @Suppress("DEPRECATION")
    override fun setTitle(title: CharSequence) {
        super.setTitle(title)
        setTaskDescription(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                TaskDescription.Builder().setLabel(title.toString()).build()
            else TaskDescription(title.toString())
        )
    }

    fun setContentView(view: LuaTable) {
        isSetViewed = true
        setContentView(LuaLayout(this).load(view, globals).touserdata(View::class.java))
    }

    fun setContentView(view: LuaTable, env: LuaTable) {
        isSetViewed = true
        setContentView(LuaLayout(this).load(view, env).touserdata(View::class.java))
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
            .setAdapter(ArrayListAdapter(this, logs), null)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    fun setDebug(bool: Boolean) {
        debug = bool
    }

    private fun initSize() {
        val windowMetrics = WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(this)
        mWidth = windowMetrics.bounds.width()
        mHeight = windowMetrics.bounds.height()
    }

    fun checkAllPermissions(): Boolean {
        if (checkCallingOrSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            try {
                // 获取应用在 Manifest 中声明的所有权限
                val requestedPermissions = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_PERMISSIONS
                ).requestedPermissions

                // 筛选出需要请求的危险权限
                val permissionsToRequest = requestedPermissions?.mapNotNull { permissionName ->
                    try {
                        val pInfo = packageManager.getPermissionInfo(permissionName, 0)
                        // 使用新的 API: getProtection() 来判断是否为危险权限
                        if (pInfo.protection == PermissionInfo.PROTECTION_DANGEROUS) {
                            // 确认该权限当前是否尚未被授予
                            if (checkCallingOrSelfPermission(permissionName) != PackageManager.PERMISSION_GRANTED) {
                                permissionName // 如果是需要请求的危险权限，则返回权限名
                            } else {
                                null // 如果已授予，则返回 null
                            }
                        } else {
                            null // 如果不是危险权限，则返回 null
                        }
                    } catch (e: PackageManager.NameNotFoundException) {
                        // 这个权限名在系统中找不到，忽略它
                        e.printStackTrace()
                        null
                    }
                } ?: emptyList() // 如果 requestedPermissions 为 null, 则返回一个空列表

                // 如果有需要请求的权限，则发起请求
                if (permissionsToRequest.isNotEmpty()) {
                    requestPermissions(permissionsToRequest.toTypedArray(), 0)
                    return false // 返回 false，表示权限请求已发出，等待用户响应
                }

            } catch (e: Exception) {
                // 捕获 getPackageInfo 可能抛出的异常
                e.printStackTrace()
            }
        }
        // 如果所有权限都已满足，或没有需要请求的权限，返回 true
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

    fun runFunc(name: String, vararg arg: Any?): Any? {
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

    private var toastTextView: TextView? = null
    fun showToast(text: String?) {
        if (!debug) return
        val now = System.currentTimeMillis()

        // 2. 判断是创建新 Toast 还是更新现有 Toast
        if (toast == null || toastTextView == null || now - lastShow > 2000) { // 延长一点间隔时间，体验更好
            // --- 创建一个新的 Toast ---

            // 重置 StringBuilder
            toastBuilder.setLength(0)
            toastBuilder.append(text)

            // 加载自定义布局
            val inflater = LayoutInflater.from(this)
            val layout = inflater.inflate(R.layout.toast_layout, null)

            // 找到 TextView 并设置文本
            toastTextView = layout.findViewById(R.id.toast_text)
            toastTextView?.text = toastBuilder.toString()

            // 创建 Toast 实例并设置自定义视图
            toast = Toast(this).apply {
                duration = Toast.LENGTH_LONG
                view = layout
            }
            toast?.show()

        } else {
            // --- 更新现有的 Toast ---

            // 追加新内容
            toastBuilder.append("\n")
            toastBuilder.append(text)

            // 直接更新 TextView 的文本
            toastTextView?.text = toastBuilder.toString()

            // 重新设置时长并再次显示，这会重置 Toast 的显示计时器
            toast?.duration = Toast.LENGTH_LONG
            toast?.show()
        }

        // 3. 更新最后显示时间
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

    fun getRootView(): ViewGroup {
        return window.decorView.rootView as ViewGroup
    }

    override fun doFile(path: String?, vararg arg: Any?): Any? {
        return globals.loadfile(path).jcall(*arg)
    }

    override fun sendMsg(msg: String?) =
        runOnUiThread {
            showToast(msg)
            logAdapter.add(msg)
            logs.add(msg)
            //Log.i("luaj", "sendMsg: $msg")
        }


    @CallLuaFunction
    override fun sendError(title: String?, exception: Exception) {
        when (runFunc("onError", title, exception)?.toString()) {
            "trace" -> sendMsg("$title: ${exception.message}\n${exception.stackTraceToString()}")
            "message" -> sendMsg(exception.message)
            "title" -> sendMsg(title)
            "log", null -> sendMsg("$title: ${exception.message}")
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

    fun registerReceiver(receiver: LuaBroadcastReceiver?, filter: IntentFilter): Intent? {
        return ContextCompat.registerReceiver(
            this,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    fun registerReceiver(ltr: OnReceiveListener?, filter: IntentFilter): Intent? {
        return ContextCompat.registerReceiver(
            this,
            LuaBroadcastReceiver(ltr),
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    fun registerReceiver(filter: IntentFilter): Intent? {
        if (mReceiver != null) unregisterReceiver(mReceiver)
        mReceiver = LuaBroadcastReceiver(this)
        return ContextCompat.registerReceiver(
            this,
            mReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

//    override fun unregisterReceiver(receiver: BroadcastReceiver?) {
//        try {
//            super.unregisterReceiver(receiver)
//        } catch (e: Exception) {
//            //Log.i("lua", "unregisterReceiver: $receiver")
//            e.printStackTrace()
//        }
//    }

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
                val res = data.getSerializableExtra(DATA, Array<Any?>::class.java)
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

    override fun getSharedData(key: String?, default: Any?): Any? {
        return PreferenceManager.getDefaultSharedPreferences(this).all[key] ?: default
    }

    @Suppress("UNCHECKED_CAST")
    override fun setSharedData(key: String?, value: Any?): Boolean {
        return PreferenceManager.getDefaultSharedPreferences(this).commit {
            if (value == null) remove(key)
            else when (value) {
                is Boolean -> putBoolean(key, value)
                is Int -> putInt(key, value)
                is Long -> putLong(key, value)
                is Float -> putFloat(key, value)
                is String -> putString(key, value)
                is LuaTable -> putStringSet(key, value.values().toSet() as MutableSet<String?>)
                is MutableSet<*> -> putStringSet(key, value as MutableSet<String?>)
                else -> return false
            }
        }
    }

    override fun regGc(obj: LuaGcable) {
        mGc.add(obj)
    }

    fun bindService(flag: Int) =
        bindService(object : ServiceConnection {
            @CallLuaFunction
            override fun onServiceConnected(comp: ComponentName?, binder: IBinder) {
                runFunc("onServiceConnected", comp, (binder as LuaBinder).service)
            }

            @CallLuaFunction
            override fun onServiceDisconnected(comp: ComponentName?) {
                runFunc("onServiceDisconnected", comp)
            }
        }, flag)


    fun bindService(conn: ServiceConnection, flag: Int): Boolean {
        val service = Intent(this, LuaService::class.java)
        var path = "service.lua"
        service.putExtra(NAME, path)
        if (luaDir != null) path = "$luaDir/$path"
        val f = File(path)
        if (f.isDirectory() && File("$path/service.lua").exists()) path += "/service.lua"
        else if ((f.isDirectory() || !f.exists()) && !path.endsWith(".lua")) path += ".lua"
        if (!File(path).exists()) throw LuaError(FileNotFoundException(path))

        service.setData("file://$path".toUri())

        return super.bindService(service, conn, flag)
    }

    fun stopService(): Boolean {
        return stopService(Intent(this, LuaService::class.java))
    }

    @JvmOverloads
    fun startService(
        path: String? = null,
        arg: Array<Any?>? = null
    ): ComponentName? {
        if (path == null) {
            // 如果 path 为 null，直接创建不带文件路径的 Intent
            val intent = Intent(this, LuaService::class.java)
            arg?.let { intent.putExtra(ARG, it) } // 如果 arg 不为 null，则添加它
            return super.startService(intent)
        }

        // path 不为 null 的情况，执行原始的文件逻辑
        var finalPath = path
        val intent = Intent(this, LuaService::class.java)
        intent.putExtra(NAME, finalPath) // 使用原始 path 作为 NAME

        // 路径处理逻辑
        if (finalPath[0] != '/' && luaDir != null) {
            finalPath = "$luaDir/$finalPath"
        }

        val f = File(finalPath)
        if (f.isDirectory && File("$finalPath/service.lua").exists()) {
            finalPath += "/service.lua"
        } else if ((f.isDirectory || !f.exists()) && !finalPath.endsWith(".lua")) {
            finalPath += ".lua"
        }

        if (!File(finalPath).exists()) {
            throw LuaError(FileNotFoundException("Service file not found: $finalPath"))
        }

        // 使用处理后的 finalPath 设置 URI
        intent.data = "file://$finalPath".toUri()

        arg?.let { intent.putExtra(ARG, it) }

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
        newActivity(1, path, arrayOfNulls(0))
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
    fun newActivity(req: Int, path: String, arg: Array<Any?>? = arrayOfNulls(0)) {
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

        intent.setData("file://$path".toUri())

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
        newActivity(1, path, `in`, out, arrayOfNulls(0))
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
        arg: Array<Any?>? = arrayOfNulls(0)
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

        intent.setData("file://$path".toUri())

        if (newDocument) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        if (arg != null) intent.putExtra(ARG, arg)
        if (newDocument) startActivity(intent)
        else startActivityForResult(intent, req)
        overridePendingTransition(false, `in`, out)
    }

    /**
     * 结束活动
     *
     * @param finishTask 是否结束任务
     */
    fun finish(finishTask: Boolean) {
        if (finishTask && (intent?.flags?.and(Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0))
            finishAndRemoveTask()
        else
            super.finish()
    }

    fun getUriForPath(path: String): Uri? {
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
    }

    fun getUriForFile(path: File): Uri? {
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", path)
    }

    fun getPathFromUri(uri: Uri?): String? {
        var path: String? = null
        uri?.let { u ->
            val p = arrayOf(MediaStore.Images.Media.DATA)
            when (u.scheme) {
                "content" -> {
                    val cursor = contentResolver.query(u, p, null, null, null)
                    cursor?.use {
                        val idx = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                        if (idx >= 0) {
                            it.moveToFirst()
                            path = it.getString(idx)
                        }
                    }
                }

                "file" -> {
                    path = u.path
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

    @JvmOverloads
    fun openFile(path: String, callback: LuaFunction? = null) {
        val file = File(path)
        // 创建Intent并设置相关标志和类型
        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_ACTIVITY_NEW_TASK
            setDataAndType(getUriForFile(file), getType(file))
        }
        if (callback != null) {
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            } else {
                callback.call()
            }
        } else startActivity(intent)
    }

    fun startPackage(pkg: String): Boolean {
        return packageManager.getLaunchIntentForPackage(pkg)
            ?.let { startActivity(it); true } == true
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

    fun getImageLoader(): ImageLoader {
        return imageLoader
    }

    fun syncLoadBitmap(data: Any?): Bitmap? {
        val request = ImageRequest.Builder(this@LuaActivity)
            .data(data)
            .build()
        val result = imageLoader.executeBlocking(request)
        return result.image?.toBitmap()
    }

    fun syncLoadDrawable(data: Any?): Drawable? {
        val request = ImageRequest.Builder(this@LuaActivity)
            .data(data)
            .build()
        val result = imageLoader.executeBlocking(request)
        return result.image?.asDrawable(resources)
    }

    fun loadBitmap(data: Any?, callback: LuaFunction) =
        imageLoader.enqueue(
            ImageRequest.Builder(this)
                .data(data)
                .target(BitmapTarget(this, callback))
                .build()
        )

    fun loadImage(data: Any?, callback: LuaFunction) =
        imageLoader.enqueue(
            ImageRequest.Builder(this)
                .data(data)
                .target(SimpleTarget(this, callback))
                .build()
        )

    fun loadImage(data: Any?, view: ImageView) = view.load(data)

    fun loadImageWithCrossFade(data: Any?, view: ImageView) = view.load(data) {
        crossfade(true)
    }

    fun dpToPx(dp: Float): Float {
        return TypedValueCompat.dpToPx(dp, resources.displayMetrics)
    }

    fun spToPx(sp: Float): Float {
        return TypedValueCompat.spToPx(sp, resources.displayMetrics)
    }

    fun addOnBackPressedCallback(callback: LuaFunction) {
        onBackPressedDispatcher.addCallback(LuaBackPressedCallback(callback))
    }

    fun delay(time: Long, callback: LuaValue) = lifecycleScope.launch {
        kotlinx.coroutines.delay(time)
        runCatching { callback.call() }.onFailure { sendError("delay", it as Exception) }
    }

    fun measureTime(action: LuaValue) = measureTimeMillis {
        action.call()
    }

    fun getMediaDir() = externalMediaDirs[0]!!

    @SuppressLint("DiscouragedPrivateApi")
    @Suppress("PrivateApi")
    fun loadXmlView(file: File) =
        runCatching {
            val cls = Class.forName("android.content.res.XmlBlock")
            val declaredMethod = cls.getDeclaredMethod("newParser")
            declaredMethod.isAccessible = true
            layoutInflater.inflate(
                declaredMethod.invoke(cls.getConstructor(ByteArray::class.java).apply {
                    isAccessible = true
                }.newInstance(file.readBytes())) as XmlResourceParser,
                null
            )
        }.getOrNull()

    private val dumpGlobals by lazy { JsePlatform.standardGlobals() }
    private fun getByteArray(path: String?): ByteArray {
        val closure = dumpGlobals.loadfile(path).checkfunction(1) as LuaClosure
        val stream = ByteArrayOutputStream()
        return try {
            DumpState.dump(closure.c, stream, true)
            stream.toByteArray()
        } catch (e: Exception) {
            throw LuaError(e)
        }
    }

    fun dumpFile(input: String?, output: String?) {
        try {
            val fos = FileOutputStream(output)
            fos.write(getByteArray(input))
            fos.close()
        } catch (e: IOException) {
            sendError("dumpFile", e)
        }
    }

    fun dynamicColor() = DynamicColors.applyToActivityIfAvailable(this)

    fun getVersionName(default: String): String {
        return try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: default
        } catch (e: PackageManager.NameNotFoundException) {
            default
        }
    }

    // Launcher 用于处理从 MANAGE_EXTERNAL_STORAGE 设置页返回的事件
    private val manageStoragePermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            // 当用户从设置页返回，我们检查权限的最终状态并回调Lua
            val isGranted = checkStoragePermission()
            runFunc(STORAGE_CALLBACK_FUNCTION, isGranted)
        }

    // Launcher 用于处理 READ/WRITE_EXTERNAL_STORAGE 权限申请的回调
    private val requestLegacyPermissionsLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { permissions ->
            // 检查所有请求的权限是否都已被授予
            val isGranted = permissions.entries.all { it.value }
            runFunc(STORAGE_CALLBACK_FUNCTION, isGranted)
        }

    /**
     * 内部会自动判断Android版本，发起正确的权限申请流程。
     * 结果将通过全局Lua函数 onPermissionResult(isGranted) 异步返回。
     */
    @CallLuaFunction
    fun requestStoragePermission() {
        if (checkStoragePermission()) {
            // 如果已经有权限，直接同步回调成功
            runFunc(STORAGE_CALLBACK_FUNCTION, true)
            return
        }

        // 根据版本选择不同的申请策略
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+，申请 MANAGE_EXTERNAL_STORAGE
            requestManageStoragePermission()
        } else {
            // Android 6-10，申请 READ/WRITE_EXTERNAL_STORAGE
            requestLegacyStoragePermissions()
        }
    }

    fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+
            Environment.isExternalStorageManager()
        } else {
            // Android 10 及以下
            val readPermission =
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE)
            val writePermission =
                ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            readPermission == PackageManager.PERMISSION_GRANTED && writePermission == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * 申请 Android 11+ 的 MANAGE_EXTERNAL_STORAGE 权限。
     */
    private fun requestManageStoragePermission() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.data = Uri.parse("package:$packageName")
            manageStoragePermissionLauncher.launch(intent)
        } catch (e: Exception) {
            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            manageStoragePermissionLauncher.launch(intent)
        }
    }

    /**
     * 申请 Android 6-10 的 READ/WRITE 权限。
     */
    private fun requestLegacyStoragePermissions() {
        val permissions = arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        )
        requestLegacyPermissionsLauncher.launch(permissions)
    }

    fun resultLauncher(callback: LuaFunction): ActivityResultLauncher<Intent> {
        return registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            callback.jcall(result)
        }
    }

    fun permissionLauncher(callback: LuaFunction): ActivityResultLauncher<String> {
        return registerForActivityResult(ActivityResultContracts.RequestPermission()) { result ->
            callback.jcall(result)
        }
    }

    companion object {
        private const val STORAGE_CALLBACK_FUNCTION = "onStorageRequestResult"
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

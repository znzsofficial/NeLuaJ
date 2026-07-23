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
import android.graphics.Color
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
import com.androlua.activity.LuaActivityFiles
import com.androlua.activity.LuaActivityImageLoader
import com.androlua.activity.LuaActivityNavigation
import com.androlua.activity.LuaActivityPermissions
import com.androlua.activity.LuaActivityServices
import com.androlua.activity.LuaActivityStorage
import com.androlua.activity.LuaActivityTheme
import com.androlua.activity.LuaActivityUI
import com.androlua.activity.LuaActivityUtils
import com.androlua.adapter.ArrayListAdapter
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.DynamicColorsOptions
import com.google.android.material.color.MaterialColors
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.nekolaska.internal.commit
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.overridePendingTransition
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import dalvik.system.DexClassLoader
import github.daisukiKaffuChino.utils.LuaThemeUtil
import github.znzsofficial.neluaj.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
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
import org.luaj.android.ext
import org.luaj.android.file
import org.luaj.android.http
import org.luaj.android.json
import org.luaj.android.loadlayout
import org.luaj.android.okhttp
import org.luaj.android.print
import org.luaj.android.printf
import org.luaj.android.res
import org.luaj.android.saf
import org.luaj.android.task
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
import org.luaj.android.thread as luajthread

@Suppress("UNUSED")
open class LuaActivity : AppCompatActivity(), ResourceFinder, LuaContext, OnReceiveListener,
    LuaMetaTable {
    
    // 将一些字段改为internal，以便辅助类可以访问
    internal lateinit var globals: Globals
    internal lateinit var logAdapter: LogAdapter
    internal var luaDir: String? = null
    internal var luaRootDir: String? = null
    internal var luaFile = "main.lua"
    internal var debug = false
    internal var isSetViewed = false
    
    private val toastBuilder = StringBuilder()
    private var toast: Toast? = null
    private var lastShow: Long = 0
    private var mExtDir: String? = null
    private var mWidth = 0
    private var mHeight = 0
    private var permissions: ArrayList<String?>? = null
    private lateinit var mLuaDexLoader: LuaDexLoader
    private val mGc = ArrayList<LuaGcable>()
    private var mReceiver: LuaBroadcastReceiver? = null
    private val registeredReceivers = ArrayList<LuaBroadcastReceiver>()
    private var pageName = "main"
    private var mOnKeyShortcut: LuaValue? = null
    private var mOnKeyDown: LuaValue? = null
    private var mOnKeyUp: LuaValue? = null
    private var mOnKeyLongPress: LuaValue? = null
    private var mOnTouchEvent: LuaValue? = null
    private var handlingError = false
    private val logEvents = MutableSharedFlow<String>(extraBufferCapacity = 128)
    
    // 创建辅助类实例
    private val permissionsHelper = LuaActivityPermissions(this)
    private val navigationHelper = LuaActivityNavigation(this)
    private val filesHelper = LuaActivityFiles(this)
    private val servicesHelper = LuaActivityServices(this)
    private val imageLoaderHelper = LuaActivityImageLoader(this)
    private val themeHelper = LuaActivityTheme(this)
    private val storageHelper = LuaActivityStorage(this)
    private val uiHelper = LuaActivityUI(this)
    private val utilsHelper = LuaActivityUtils(this)
    
    val themeUtil = LuaThemeUtil(this)
    
    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    @CallLuaFunction
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        luaDir = filesDir.absolutePath
        luaRootDir = luaDir
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
        luaRootDir = checkProjectDir(File(luaDir!!)).absolutePath
        initSize()
        pageName = File(luaFile).getName()
        val idx = pageName.lastIndexOf(".")
        if (idx > 0) pageName = pageName.substring(0, idx)
        sLuaActivityMap.getOrPut(pageName) { ArrayDeque() }.addLast(this)
        mLuaDexLoader = LuaDexLoader(this, luaRootDir)
        mLuaDexLoader.loadLibs()
        globals = JsePlatform.standardGlobals()
        // globals.finder = this;
        globals.m = this
        logAdapter = LogAdapter()
        lifecycleScope.launch {
            logEvents.collect { msg ->
                showToast(msg)
                logAdapter.add(msg)
                addLog(msg)
            }
        }
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
                it.load(ext())
                it.load(okhttp())
                it.jset("saf", saf(this))
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
    
    private fun showLogView(isError: Boolean) = uiHelper.showLogView(isError)
    
    fun setAllowThread(bool: Boolean) = utilsHelper.setAllowThread(bool)
    
    @CallLuaFunction
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        runFunc("onRequestPermissionsResult", requestCode, permissions, grantResults)
    }
    
    @Deprecated("Use Activity Result APIs instead.")
    @CallLuaFunction
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        navigationHelper.resetLauncherActivityResultDispatched()
        super.onActivityResult(requestCode, resultCode, data)
        if (!navigationHelper.wasLauncherActivityResultDispatched()) {
            navigationHelper.dispatchLegacyActivityResult(requestCode, resultCode, data)
        }
    }

    /**
     * Shared element / activity reenter callback.
     * Lua: function onActivityReenter(resultCode, data) end
     */
    @CallLuaFunction
    override fun onActivityReenter(resultCode: Int, data: Intent?) {
        super.onActivityReenter(resultCode, data)
        runFunc("onActivityReenter", resultCode, data)
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
        val rootDir = luaRootDir ?: luaDir ?: return
        if (!File(rootDir, "init.lua").exists()) return
        try {
            val env = LuaTable()
            globals.loadfile(File(rootDir, "init.lua").absolutePath, env).call()
            var v = env.get("appname")
            if (v.isstring()) setTitle(v.tojstring())
            v = env.get("app_name")
            if (v.isstring()) setTitle(v.tojstring())
            v = env.get("debugmode")
            if (v.isboolean()) setDebug(v.toboolean())
            v = env.get("debug_mode")
            if (v.isboolean()) setDebug(v.toboolean())
            v = env.get("theme")
            if (v.isint()) setTheme(v.toint())
            else if (v.isstring()) setTheme(
                android.R.style::class.java.getField(v.tojstring()).getInt(null)
            )
            v = env.get("NeLuaJ_Theme")
            if (v.isstring()) setTheme(
                R.style::class.java.getField(v.tojstring()).getInt(null)
            )
        } catch (e: Exception) {
            sendError("init.lua Error", e)
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
    
    fun setContentView(view: LuaTable) = uiHelper.setContentView(view)
    
    fun setContentView(view: LuaTable, env: LuaTable) = uiHelper.setContentView(view, env)
    
    fun setFragment(fragment: Fragment) = uiHelper.setFragment(fragment)
    
    fun showLogs() = uiHelper.showLogs()
    
    fun setDebug(bool: Boolean) {
        debug = bool
    }
    
    private fun initSize() {
        val windowMetrics = WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(this)
        mWidth = windowMetrics.bounds.width()
        mHeight = windowMetrics.bounds.height()
    }
    
    fun checkAllPermissions(): Boolean = permissionsHelper.checkAllPermissions()
    
    fun checkPermission(permission: String?): Boolean = permissionsHelper.checkPermission(permission)
    
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
    
    override fun findResource(name: String): InputStream? = filesHelper.findResource(name)
    
    fun checkResource(name: String): Boolean = filesHelper.checkResource(name)
    
    override fun findFile(filename: String): String = filesHelper.findFile(filename)
    
    fun showToast(text: String?) = uiHelper.showToast(text)
    
    override fun getClassLoaders(): ArrayList<ClassLoader?>? {
        return mLuaDexLoader.classLoaders
    }
    
    fun loadDex(path: String?): DexClassLoader? {
        return mLuaDexLoader.loadDex(path)
    }
    
    override fun call(func: String?, vararg args: Any?) {
        lifecycleScope.launch(Dispatchers.Main.immediate) { globals.get(func).jcall(*args) }
    }
    
    override fun set(name: String?, value: Any?) {
        lifecycleScope.launch(Dispatchers.Main.immediate) { globals.jset(name, value) }
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
        return File(luaRootDir ?: luaDir, path).absolutePath
    }
    
    override fun getLuaPath(dir: String, name: String): String {
        return File(File(luaRootDir ?: luaDir, dir), name).absolutePath
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
    
    fun getDecorView(): ViewGroup = uiHelper.getDecorView()
    
    fun getRootView(): ViewGroup = uiHelper.getRootView()
    
    override fun doFile(path: String?, vararg arg: Any?): Any? {
        return globals.loadfile(path).jcall(*arg)
    }
    
    override fun sendMsg(msg: String?) {
        logEvents.tryEmit(msg.orEmpty())
    }
    
    @CallLuaFunction
    override fun sendError(title: String?, exception: Exception) {
        if (handlingError) {
            sendMsg("$title: ${exception.message}")
            return
        }
        handlingError = true
        try {
            when (runFunc("onError", title, exception)?.toString()) {
                "trace" -> sendMsg("$title: ${exception.message}\n${exception.stackTraceToString()}")
                "message" -> sendMsg(exception.message)
                "title" -> sendMsg(title)
                "log", null -> sendMsg("$title: ${exception.message}")
            }
        } finally {
            handlingError = false
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
        val result = ContextCompat.registerReceiver(
            this,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        if (receiver != null && !registeredReceivers.contains(receiver)) {
            registeredReceivers.add(receiver)
        }
        return result
    }
    
    fun registerReceiver(ltr: OnReceiveListener?, filter: IntentFilter): Intent? {
        val receiver = LuaBroadcastReceiver(ltr)
        val result = ContextCompat.registerReceiver(
            this,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        registeredReceivers.add(receiver)
        return result
    }
    
    fun registerReceiver(filter: IntentFilter): Intent? {
        mReceiver?.let {
            runCatching { unregisterReceiver(it) }
            registeredReceivers.remove(it)
        }
        mReceiver = LuaBroadcastReceiver(this)
        val result = ContextCompat.registerReceiver(
            this,
            mReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        registeredReceivers.add(mReceiver!!)
        return result
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
        registeredReceivers.forEach { receiver ->
            runCatching { unregisterReceiver(receiver) }
        }
        registeredReceivers.clear()
        mReceiver = null
        sLuaActivityMap[pageName]?.let { stack ->
            stack.removeAll { it === this }
            if (stack.isEmpty()) sLuaActivityMap.remove(pageName)
        }
        if (equals(sActivity)) sActivity = null
        super.onDestroy()
    }
    
    fun result(data: Array<Any?>?) = navigationHelper.result(data)
    
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
    
    override fun getGlobalData(): Map<*, *> = storageHelper.getGlobalData()
    
    override fun getSharedData(): MutableMap<String?, *>? = storageHelper.getSharedData()
    
    override fun getSharedData(key: String?): Any? = storageHelper.getSharedData(key)
    
    override fun getSharedData(key: String?, default: Any?): Any? = storageHelper.getSharedData(key, default)
    
    @Suppress("UNCHECKED_CAST")
    override fun setSharedData(key: String?, value: Any?): Boolean = storageHelper.setSharedData(key, value)
    
    override fun regGc(obj: LuaGcable) {
        mGc.add(obj)
    }
    
    fun bindService(flag: Int) = servicesHelper.bindService(flag)
    
    fun bindService(conn: ServiceConnection, flag: Int): Boolean = servicesHelper.bindService(conn, flag)
    
    fun stopService(): Boolean = servicesHelper.stopService()
    
    @JvmOverloads
    fun startService(
        path: String? = null,
        arg: Array<Any?>? = null
    ): ComponentName? = servicesHelper.startService(path, arg)
    
    /**
     * 新建活动
     *
     * @param path        文件路径
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, newDocument: Boolean) = navigationHelper.newActivity(path, newDocument)
    
    /**
     * 新建活动
     *
     * @param path        文件路径
     * @param arg         参数数组
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, arg: Array<Any?>?, newDocument: Boolean) = navigationHelper.newActivity(path, arg, newDocument)
    
    /**
     * 新建活动
     *
     * @param req         请求码
     * @param path        文件路径
     * @param newDocument 是否为新文档
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, newDocument: Boolean) = navigationHelper.newActivity(req, path, newDocument)
    
    /**
     * 新建活动
     *
     * @param path 文件路径
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String) = navigationHelper.newActivity(path)
    
    /**
     * 新建活动
     *
     * @param path 文件路径
     * @param arg  参数数组
     * @throws FileNotFoundException 文件未找到异常
     */
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, arg: Array<Any?>?) = navigationHelper.newActivity(path, arg)
    
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
    fun newActivity(req: Int, path: String, arg: Array<Any?>? = arrayOfNulls(0)) = navigationHelper.newActivity(req, path, arg)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, newDocument: Boolean) = navigationHelper.newActivity(path, `in`, out, newDocument)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, arg: Array<Any?>?, newDocument: Boolean) = navigationHelper.newActivity(path, `in`, out, arg, newDocument)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(req: Int, path: String, `in`: Int, out: Int, newDocument: Boolean) = navigationHelper.newActivity(req, path, `in`, out, newDocument)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int) = navigationHelper.newActivity(path, `in`, out)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(path: String, `in`: Int, out: Int, arg: Array<Any?>?) = navigationHelper.newActivity(path, `in`, out, arg)
    
    @JvmOverloads
    @Throws(FileNotFoundException::class)
    fun newActivity(
        req: Int,
        path: String,
        `in`: Int,
        out: Int,
        arg: Array<Any?>? = arrayOfNulls(0)
    ) = navigationHelper.newActivity(req, path, `in`, out, arg)
    
    fun newActivity(req: Int, path: String, arg: Array<Any?>?, newDocument: Boolean) = navigationHelper.newActivity(req, path, arg, newDocument)
    
    @Throws(FileNotFoundException::class)
    fun newActivity(
        req: Int,
        path: String,
        `in`: Int,
        out: Int,
        arg: Array<Any?>?,
        newDocument: Boolean
    ) = navigationHelper.newActivity(req, path, `in`, out, arg, newDocument)
    
    /**
     * 结束活动
     *
     * @param finishTask 是否结束任务
     */
    fun finish(finishTask: Boolean) = navigationHelper.finish(finishTask)
    
    fun getUriForPath(path: String): Uri? = filesHelper.getUriForPath(path)
    
    fun getUriForFile(path: File): Uri? = filesHelper.getUriForFile(path)
    
    fun getPathFromUri(uri: Uri?): String? = filesHelper.getPathFromUri(uri)
    
    @JvmOverloads
    fun openFile(path: String, callback: LuaFunction? = null) = filesHelper.openFile(path, callback)
    
    fun startPackage(pkg: String): Boolean = filesHelper.startPackage(pkg)
    
    fun installApk(path: String) = filesHelper.installApk(path)
    
    fun shareFile(path: String) = filesHelper.shareFile(path)
    
    fun isNightMode() = themeHelper.isNightMode()
    
    fun getFilter(color: Int): ColorFilter = themeHelper.getFilter(color)
    
    fun getImageLoader(): ImageLoader = imageLoaderHelper.getImageLoader()
    
    fun syncLoadBitmap(data: Any?): Bitmap? = imageLoaderHelper.syncLoadBitmap(data)
    
    fun syncLoadDrawable(data: Any?): Drawable? = imageLoaderHelper.syncLoadDrawable(data)
    
    fun loadBitmap(data: Any?, callback: LuaFunction) = imageLoaderHelper.loadBitmap(data, callback)
    
    fun loadImage(data: Any?, callback: LuaFunction) = imageLoaderHelper.loadImage(data, callback)
    
    fun loadImage(data: Any?, view: ImageView) = imageLoaderHelper.loadImage(data, view)
    
    fun loadImageWithCrossFade(data: Any?, view: ImageView) = imageLoaderHelper.loadImageWithCrossFade(data, view)
    
    fun dpToPx(dp: Float): Float = utilsHelper.dpToPx(dp)
    
    fun spToPx(sp: Float): Float = utilsHelper.spToPx(sp)
    
    fun addOnBackPressedCallback(callback: LuaFunction) = utilsHelper.addOnBackPressedCallback(callback)
    
    fun delay(time: Long, callback: LuaValue) = utilsHelper.delay(time, callback)
    
    fun measureTime(action: LuaValue) = utilsHelper.measureTime(action)
    
    fun getMediaDir() = filesHelper.getMediaDir()
    
    @SuppressLint("DiscouragedPrivateApi")
    @Suppress("PrivateApi")
    fun loadXmlView(file: File) = filesHelper.loadXmlView(file)
    
    fun dumpFile(input: String?, output: String?) = filesHelper.dumpFile(input, output)
    
    fun dynamicColor() = themeHelper.dynamicColor()
    
    /**
     * Apply dynamic colors based on a seed color.
     * Generates a full Material 3 color scheme from the given seed color
     * and applies it to the Activity. After calling this, themeUtil will
     * reflect the new color scheme.
     *
     * Usage in Lua: this.dynamicColor(0xFF6750A4)
     */
    fun dynamicColor(seedColor: Int) = themeHelper.dynamicColor(seedColor)
    
    /**
     * Harmonize a color with the current theme's primary color.
     * Returns a new color that is visually harmonious with the theme.
     *
     * Usage in Lua: local harmonized = this.harmonizeColor(0xFFFF0000)
     */
    fun harmonizeColor(color: Int): Int = themeHelper.harmonizeColor(color)
    
    /**
     * Harmonize two arbitrary colors.
     *
     * Usage in Lua: local result = this.harmonizeColor(color1, color2)
     */
    fun harmonizeColor(color: Int, withColor: Int): Int = themeHelper.harmonizeColor(color, withColor)
    
    /**
     * Check if a color is considered light.
     *
     * Usage in Lua: local light = this.isColorLight(0xFFFFFFFF)
     */
    fun isColorLight(color: Int): Boolean = themeHelper.isColorLight(color)
    
    fun getVersionName(default: String): String = utilsHelper.getVersionName(default)
    
    /**
     * 内部会自动判断Android版本，发起正确的权限申请流程。
     * 结果将通过全局Lua函数 onStorageRequestResult(isGranted) 异步返回。
     */
    @CallLuaFunction
    fun requestStoragePermission() = permissionsHelper.requestStoragePermission()
    
    fun checkStoragePermission(): Boolean = permissionsHelper.checkStoragePermission()
    
    fun resultLauncher(callback: LuaFunction): ActivityResultLauncher<Intent> = navigationHelper.resultLauncher(callback)
    
    fun permissionLauncher(callback: LuaFunction): ActivityResultLauncher<String> = navigationHelper.permissionLauncher(callback)
    
    companion object {
        private const val ARG = "arg"
        private const val DATA = "data"
        private const val NAME = "name"
        private const val MAX_LOGS = 5000
        
        @JvmField
        var logs = ArrayList<String?>()
        
        private fun addLog(msg: String?) {
            logs.add(msg)
            while (logs.size > MAX_LOGS) {
                logs.removeAt(0)
            }
        }
        
        @JvmField
        var sActivity: LuaActivity? = null
        /** pageName → 同名实例栈（后打开的在栈顶）；getActivity 返回栈顶 */
        private val sLuaActivityMap = HashMap<String?, ArrayDeque<LuaActivity>>()
        
        @JvmStatic
        fun logError(title: String?, msg: Exception) {
            sActivity?.sendMsg(title + ": " + msg.message)
            logs.add("$title: $msg")
        }
        
        @JvmStatic
        fun getActivity(name: String?): LuaActivity? {
            return sLuaActivityMap[name]?.lastOrNull()
        }
    }
}

package com.androlua.activity

import android.app.Activity
import android.content.Intent
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityOptionsCompat
import androidx.core.net.toUri
import com.androlua.LuaActivity
import com.androlua.LuaActivityX
import com.nekolaska.ktx.overridePendingTransition
import com.nekolaska.ktx.toLuaValue
import org.luaj.LuaFunction
import java.io.FileNotFoundException
import java.util.ArrayDeque

class LuaActivityNavigation(private val activity: LuaActivity) {
    
    companion object {
        private const val ARG = "arg"
        private const val DATA = "data"
        private const val NAME = "name"
    }
    
    private data class PendingLuaActivityResult(val requestCode: Int, val name: String?)
    
    private val pendingResults = ArrayDeque<PendingLuaActivityResult>()
    private val pendingResultCallbacks = ArrayDeque<LuaFunction>()
    private val pendingPermissionCallbacks = ArrayDeque<LuaFunction>()
    private var launcherActivityResultDispatched = false
    
    @Suppress("DEPRECATION")
    private val activityLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            launcherActivityResultDispatched = true
            val pending = pendingResults.pollFirst()
            val requestCode = pending?.requestCode ?: 0
            val name = pending?.name
            dispatchActivityResult(requestCode, result.resultCode, result.data, name)
        }
    
    private val sharedResultLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            launcherActivityResultDispatched = true
            pendingResultCallbacks.pollFirst()?.safeCall(result.toLuaValue())
        }
    
    private val sharedPermissionLauncher: ActivityResultLauncher<String> =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { result ->
            pendingPermissionCallbacks.pollFirst()?.safeCall(result.toLuaValue())
        }
    
    private fun buildLuaIntent(path: String, arg: Array<Any?>?, newDocument: Boolean): Intent {
        var resolved =
            if (path.startsWith("/")) path else "${activity.luaRootDir ?: activity.luaDir ?: activity.filesDir.absolutePath}/$path"
        val file = java.io.File(resolved)
        if (file.isDirectory && java.io.File(file, "main.lua").exists()) resolved =
            "${file.absolutePath}/main.lua"
        else if ((file.isDirectory || !file.exists()) && !resolved.endsWith(".lua")) resolved += ".lua"
        require(java.io.File(resolved).exists()) { "File not found: $resolved" }
        return Intent(
            activity,
            if (newDocument) LuaActivityX::class.java else LuaActivity::class.java
        ).apply {
            setData("file://$resolved".toUri())
            putExtra(NAME, path)
            if (newDocument) addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            arg?.let { putExtra(ARG, it) }
        }
    }
    
    private fun launchLuaActivity(
        req: Int,
        intent: Intent,
        newDocument: Boolean,
        pendingName: String?
    ) {
        if (newDocument) {
            activity.startActivity(intent)
        } else {
            check(pendingResults.isEmpty()) { "Previous Lua activity result is still pending" }
            val pending = PendingLuaActivityResult(req, pendingName)
            pendingResults.addLast(pending)
            try {
                activityLauncher.launch(intent)
            } catch (e: RuntimeException) {
                pendingResults.removeLastOccurrence(pending)
                throw e
            }
        }
    }

    fun resetLauncherActivityResultDispatched() {
        launcherActivityResultDispatched = false
    }
    
    fun wasLauncherActivityResultDispatched(): Boolean {
        val dispatched = launcherActivityResultDispatched
        launcherActivityResultDispatched = false
        return dispatched
    }
    
    fun dispatchLegacyActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        dispatchActivityResult(requestCode, resultCode, data, data?.getStringExtra(NAME))
    }
    
    @Suppress("DEPRECATION")
    private fun dispatchActivityResult(requestCode: Int, resultCode: Int, data: Intent?, name: String?) {
        if (data != null && name != null) {
            val res = when (val serializable = data.getSerializableExtra(DATA)) {
                is Array<*> -> serializable
                is List<*> -> serializable.toTypedArray()
                null -> null
                else -> arrayOf(serializable)
            }
            if (res == null) activity.runFunc("onResult", name)
            else {
                val args = arrayOfNulls<Any>(res.size + 1)
                args[0] = name
                System.arraycopy(res, 0, args, 1, res.size)
                val handled = activity.runFunc("onResult", *args)
                if (handled is Boolean && handled) return
            }
        }
        activity.runFunc("onActivityResult", requestCode, resultCode, data)
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
    
    fun newActivity(req: Int, path: String, arg: Array<Any?>?, newDocument: Boolean) {
        val intent = buildLuaIntent(path, arg, newDocument)
        launchLuaActivity(req, intent, newDocument, path)
    }
    
    @Throws(FileNotFoundException::class)
    fun newActivity(
        req: Int,
        path: String,
        `in`: Int,
        out: Int,
        arg: Array<Any?>?,
        newDocument: Boolean
    ) {
        val intent = buildLuaIntent(path, arg, newDocument)
        launchLuaActivity(req, intent, newDocument, path)
        activity.overridePendingTransition(false, `in`, out)
    }
    
    /**
     * 结束活动
     *
     * @param finishTask 是否结束任务
     */
    fun finish(finishTask: Boolean) {
        if (finishTask && (activity.intent?.flags?.and(Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0))
            activity.finishAndRemoveTask()
        else
            activity.finish()
    }
    
    fun result(data: Array<Any?>?) {
        val res = Intent()
        res.putExtra(NAME, activity.intent.getStringExtra(NAME))
        res.putExtra(DATA, data)
        activity.setResult(Activity.RESULT_OK, res)
        activity.finish()
    }
    
    fun resultLauncher(callback: LuaFunction): ActivityResultLauncher<Intent> {
        return object : ActivityResultLauncher<Intent>() {
            override val contract: ActivityResultContract<Intent, ActivityResult> =
                ActivityResultContracts.StartActivityForResult()
            
            override fun launch(input: Intent, options: ActivityOptionsCompat?) {
                check(pendingResultCallbacks.isEmpty()) { "Previous activity result is still pending" }
                pendingResultCallbacks.addLast(callback)
                try {
                    sharedResultLauncher.launch(input, options)
                } catch (e: RuntimeException) {
                    pendingResultCallbacks.removeLastOccurrence(callback)
                    throw e
                }
            }
            
            override fun unregister() = Unit
        }
    }
    
    fun permissionLauncher(callback: LuaFunction): ActivityResultLauncher<String> {
        return object : ActivityResultLauncher<String>() {
            override val contract: ActivityResultContract<String, Boolean> =
                ActivityResultContracts.RequestPermission()
            
            override fun launch(input: String, options: ActivityOptionsCompat?) {
                check(pendingPermissionCallbacks.isEmpty()) { "Previous permission result is still pending" }
                pendingPermissionCallbacks.addLast(callback)
                try {
                    sharedPermissionLauncher.launch(input, options)
                } catch (e: RuntimeException) {
                    pendingPermissionCallbacks.removeLastOccurrence(callback)
                    throw e
                }
            }
            
            override fun unregister() = Unit
        }
    }
    
    private fun LuaFunction.safeCall(arg: org.luaj.LuaValue) {
        try {
            call(arg)
        } catch (e: Exception) {
            activity.sendError("activity result callback", e)
        }
    }
}

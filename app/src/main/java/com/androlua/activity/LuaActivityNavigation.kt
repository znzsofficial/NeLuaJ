package com.androlua.activity

import android.content.Intent
import android.util.SparseArray
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.net.toUri
import com.androlua.LuaActivity
import com.androlua.LuaActivityX
import com.nekolaska.ktx.overridePendingTransition
import com.nekolaska.ktx.toLuaValue
import java.io.FileNotFoundException

class LuaActivityNavigation(private val activity: LuaActivity) {
    
    companion object {
        private const val ARG = "arg"
        private const val DATA = "data"
        private const val NAME = "name"
    }
    
    private val pendingResults = SparseArray<String?>()
    private var lastRequestCode = 0
    
    @Suppress("DEPRECATION")
    private val activityLauncher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val requestCode = lastRequestCode
            val name = pendingResults.get(requestCode)
            pendingResults.remove(requestCode)
            
            val data = result.data
            if (data != null) {
                val res = when (val serializable = data.getSerializableExtra(DATA)) {
                    is Array<*> -> serializable
                    is List<*> -> serializable.toTypedArray()
                    null -> null
                    else -> arrayOf(serializable)
                }
                //val res = data.getSerializableExtra(DATA, Array<Any?>::class.java)
                if (name != null) {
                    if (res == null) activity.runFunc("onResult", name)
                    else {
                        val args = arrayOfNulls<Any>(res.size + 1)
                        args[0] = name
                        System.arraycopy(res, 0, args, 1, res.size)
                        val handled = activity.runFunc("onResult", *args)
                        if (handled is Boolean && handled) return@registerForActivityResult
                    }
                }
            }
            activity.runFunc("onActivityResult", requestCode, result.resultCode, data)
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
            lastRequestCode = req
            pendingResults.put(req, pendingName)
            activityLauncher.launch(intent)
        }
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
        activity.setResult(0, res)
        activity.finish()
    }
    
    fun resultLauncher(callback: org.luaj.LuaFunction): ActivityResultLauncher<Intent> {
        return activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            callback.call(result.toLuaValue())
        }
    }
    
    fun permissionLauncher(callback: org.luaj.LuaFunction): ActivityResultLauncher<String> {
        return activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { result ->
            callback.call(result.toLuaValue())
        }
    }
}
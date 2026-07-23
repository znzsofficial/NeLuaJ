package com.androlua

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.core.content.edit
import androidx.lifecycle.lifecycleScope
import dalvik.system.ZipPathValidator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipFile

/**
 * 启动页：APK 更新后将 assets/ 解到 luaDir，再进入 [LuaActivity]。
 * lastUpdateTime 仅在解压成功后写入，失败下次启动会重试。
 */
class SplashWelcome : ComponentActivity() {
    private lateinit var app: LuaApplication
    private lateinit var localDir: String
    private var isVersionChanged = false
    private var mVersionName: String? = null
    private var mOldVersionName: String? = null
    private var pendingLastUpdateTime: Long = 0

    @CallLuaFunction
    public override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = application as LuaApplication
        localDir = app.luaDir
        if (checkInfo()) {
            LuaApplication.instance.setSharedData("UnZiped", false)
            lifecycleScope.launch {
                val ok = withContext(Dispatchers.IO) {
                    runCatching { unApk("assets/", localDir) }
                        .onFailure { Log.e(TAG, "unApk failed", it) }
                        .isSuccess
                }
                if (ok) {
                    commitUpdateMarker()
                    LuaApplication.instance.setSharedData("UnZiped", true)
                    startActivity()
                } else {
                    // 不写 lastUpdateTime，下次冷启动会再解
                    LuaApplication.instance.setSharedData("UnZiped", false)
                    Log.e(TAG, "assets extract failed; will retry next launch")
                    // 仍尝试进入，避免永久卡在欢迎页；资源可能不完整
                    startActivity()
                }
            }
        } else {
            LuaApplication.instance.setSharedData("UnZiped", true)
            startActivity()
        }
    }

    private fun startActivity() {
        val intent = Intent(this@SplashWelcome, LuaActivity::class.java)
        if (isVersionChanged) {
            intent.putExtra("isVersionChanged", isVersionChanged)
            intent.putExtra("newVersionName", mVersionName)
            intent.putExtra("oldVersionName", mOldVersionName)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        finish()
    }

    /**
     * @return true 需要从 APK 解出 assets
     */
    private fun checkInfo(): Boolean {
        try {
            val packageInfo = packageManager.getPackageInfo(this.packageName, 0)
            val lastTime = packageInfo.lastUpdateTime
            val versionName = packageInfo.versionName
            val info = getSharedPreferences("appInfo", 0)
            val oldVersionName = info.getString("versionName", "")
            mVersionName = versionName
            mOldVersionName = oldVersionName
            if (versionName != oldVersionName) {
                info.edit { putString("versionName", versionName) }
                isVersionChanged = true
            }
            val oldLastTime = info.getLong("lastUpdateTime", 0)
            if (oldLastTime != lastTime) {
                // 成功解压后再 commitUpdateMarker
                pendingLastUpdateTime = lastTime
                return true
            }
        } catch (e: PackageManager.NameNotFoundException) {
            Log.e(TAG, "checkInfo", e)
        }
        return false
    }

    private fun commitUpdateMarker() {
        if (pendingLastUpdateTime == 0L) return
        getSharedPreferences("appInfo", 0).edit {
            putLong("lastUpdateTime", pendingLastUpdateTime)
        }
        pendingLastUpdateTime = 0
    }

    /**
     * 将 APK 内 [dir] 前缀条目解到 [extDir]。
     * 全量覆盖写出；.dex 设只读。
     * ZipFile 非线程安全：列举一把；写出时每线程各自 open APK。
     */
    private fun unApk(dir: String, extDir: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ZipPathValidator.clearCallback()
        }
        val destRoot = File(extDir)
        if (!destRoot.exists()) destRoot.mkdirs()
        val destCanonical = destRoot.canonicalPath
        val destPrefix = if (destCanonical.endsWith(File.separator)) destCanonical
        else destCanonical + File.separator

        val apkPath = applicationInfo.publicSourceDir
        val prefixLen = dir.length
        // 待写：entry 名（完整 zip 路径）
        val fileNames = ArrayList<String>(256)

        ZipFile(apkPath).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                val name = entry.name
                if (!name.startsWith(dir)) continue
                val rel = name.substring(prefixLen)
                if (rel.isEmpty() || rel.contains("..")) continue
                val out = File(destRoot, rel)
                val outPath = out.canonicalPath
                if (outPath != destCanonical && !outPath.startsWith(destPrefix)) continue
                if (entry.isDirectory) {
                    if (!out.exists()) out.mkdirs()
                } else {
                    fileNames.add(name)
                }
            }
        }

        val queue = ConcurrentLinkedQueue(fileNames)
        val errors = ConcurrentLinkedQueue<Throwable>()
        val written = AtomicInteger(0)
        val workers = Runtime.getRuntime().availableProcessors().coerceIn(2, 8)
        val pool = Executors.newFixedThreadPool(workers)

        // 每线程一个 ZipFile（非线程安全），从队列取 entry 写出
        repeat(workers) {
            pool.execute {
                ZipFile(apkPath).use { zip ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        val entryName = queue.poll() ?: break
                        try {
                            writeEntry(zip, entryName, prefixLen, destRoot, buffer)
                            written.incrementAndGet()
                        } catch (t: Throwable) {
                            errors.add(t)
                        }
                    }
                }
            }
        }

        pool.shutdown()
        if (!pool.awaitTermination(30, TimeUnit.MINUTES)) {
            pool.shutdownNow()
            throw IOException("assets extract timed out")
        }

        val first = errors.peek()
        if (first != null) {
            throw IOException(
                "assets extract failed (${errors.size} errors), written=${written.get()}",
                first
            )
        }
        Log.i(TAG, "assets extract ok written=${written.get()}")
    }

    private fun writeEntry(
        zip: ZipFile,
        entryName: String,
        prefixLen: Int,
        destRoot: File,
        buffer: ByteArray,
    ) {
        val entry = zip.getEntry(entryName)
            ?: throw IOException("missing zip entry: $entryName")
        val target = File(destRoot, entryName.substring(prefixLen))
        if (target.exists() && target.isDirectory) {
            LuaUtil.rmDir(target)
        }
        val parent = target.parentFile
            ?: throw IOException("no parent for ${target.absolutePath}")
        if (!parent.isDirectory && !parent.mkdirs()) {
            throw IOException("cannot create directory: ${parent.absolutePath}")
        }

        // 先写临时文件，再替换目标：不碰只读 .dex 的 open，失败也不留下半截
        val tmp = File(parent, ".${target.name}.tmp")
        try {
            zip.getInputStream(entry).use { input ->
                FileOutputStream(tmp).use { output ->
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                    }
                }
            }
            if (target.exists() && !target.delete()) {
                // 只读 dex：先恢复可写再删
                target.setWritable(true)
                if (!target.delete()) {
                    throw IOException("cannot replace: ${target.absolutePath}")
                }
            }
            if (!tmp.renameTo(target)) {
                throw IOException("rename failed: ${tmp.name} -> ${target.name}")
            }
            // ART 要求已加载 dex 不可写
            if (target.name.endsWith(".dex", ignoreCase = true)) {
                target.setReadOnly()
            }
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }

    companion object {
        private const val TAG = "SplashWelcome"
        private const val BUFFER_SIZE = 16 * 1024
    }
}

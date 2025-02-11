package com.androlua

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import dalvik.system.ZipPathValidator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import androidx.core.content.edit

class SplashWelcome : ComponentActivity() {
    private var isUpdate = false
    private lateinit var app: LuaApplication
    private lateinit var localDir: String
    private var mLastTime: Long = 0
    private var mOldLastTime: Long = 0
    private var isVersionChanged = false
    private var mVersionName: String? = null
    private var mOldVersionName: String? = null

    @CallLuaFunction
    public override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = application as LuaApplication
        localDir = app.luaDir
        if (checkInfo()) {
            LuaApplication.instance.setSharedData("UnZiped", false)
            lifecycleScope.launch {
                withContext(Dispatchers.IO) {
                    runCatching {
                        unApk("assets/", localDir)
                    }
                }
                startActivity()
                LuaApplication.instance.setSharedData("UnZiped", true)
            }
        } else {
            startActivity()
        }
    }

    @Suppress("KotlinConstantConditions")
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
        return
        // overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out
        //
        // );
    }

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
                info.edit {
                    putString("versionName", versionName)
                }
                isVersionChanged = true
            }
            val oldLastTime = info.getLong("lastUpdateTime", 0)
            if (oldLastTime != lastTime) {
                info.edit {
                    putLong("lastUpdateTime", lastTime)
                }
                isUpdate = true
                mLastTime = lastTime
                mOldLastTime = oldLastTime
                return true
            }
        } catch (e: PackageManager.NameNotFoundException) {
            e.printStackTrace()
        }
        return false
    }

    private var zipFile: ZipFile? = null
    private var destPath: String? = null

    private fun unApk(dir: String, extDir: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ZipPathValidator.clearCallback()
        }
        val dirList = ArrayList<String>()
        val threadPool =
            Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())
        val i = dir.length
        destPath = extDir
        zipFile = ZipFile(applicationInfo.publicSourceDir)
        val entries = zipFile!!.entries()
        val inzipfile = ArrayList<ZipEntry>()
        while (entries.hasMoreElements()) {
            val zipEntry = entries.nextElement()
            val name = zipEntry.name
            if (name.indexOf(dir) != 0) continue
            val path = name.substring(i)
            val fp = extDir + File.separator + path
            if (!zipEntry.isDirectory) {
                inzipfile.add(zipEntry)
                dirList.add(fp + File.separator)
                continue
            }
            val file = File(fp)
            if (!file.exists()) {
                file.mkdirs()
            }
        }
        val iter: Iterator<ZipEntry> = inzipfile.iterator()
        while (iter.hasNext()) { // 文件处理
            val zipEntry = iter.next()
            val name = zipEntry.name
            val path = name.substring(i)
            val fp = extDir + File.separator + path
            val watchiter: Iterator<String> = dirList.iterator()
            var find = false
            while (watchiter.hasNext()) {
                val dirListWatchNext = watchiter.next()
                if (fp.startsWith(dirListWatchNext)) {
                    find = true
                    break
                }
            }
            if (find) continue
            threadPool.execute(FileWritingTask(zipEntry, path))
        }
        threadPool.shutdown()
        try {
            threadPool.awaitTermination(Long.MAX_VALUE, TimeUnit.NANOSECONDS)
        } catch (e: InterruptedException) {
            e.printStackTrace()
            throw RuntimeException("ExecutorService was interrupted.")
        }
        zipFile!!.close()
    }

    private inner class FileWritingTask(
        private val zipEntry: ZipEntry,
        private val path: String
    ) : Runnable {
        override fun run() {
            val file = File(destPath + File.separator + path)
            if (file.exists() && file.isDirectory) { // 保证文件写入，文件夹就算了……
                LuaUtil.rmDir(file)
            }
            val parentFile = file.parentFile
            if (parentFile != null) {
                if (!parentFile.exists()) {
                    parentFile.mkdirs()
                }
            }
            if (parentFile?.isDirectory == true) {
                try {
                    val inputStream = zipFile!!.getInputStream(zipEntry)
                    val outputStream: OutputStream = FileOutputStream(file)
                    val buffer = ByteArray(2048)
                    var n: Int
                    while (inputStream.read(buffer).also { n = it } >= 0) {
                        outputStream.write(buffer, 0, n)
                    }
                    outputStream.close()
                    // dex文件不可写
                    if (path.endsWith(".dex", ignoreCase = true)) file.setReadOnly()
                } catch (e: IOException) {
                    e.printStackTrace()
                    throw RuntimeException("unzip error at file " + file.absolutePath + ".")
                }
            } else {
                throw RuntimeException(
                    "ParentFile( path = \""
                            + parentFile?.absolutePath
                            + "\" ) is not a directory, the application can't write the File( name = \""
                            + file.name
                            + "\" ) in a file."
                )
            }
        }
    }
}

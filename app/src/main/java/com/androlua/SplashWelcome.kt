package com.androlua

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
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

// import net.lingala.zip4j.ZipFile;
// import net.lingala.zip4j.exception.ZipException;
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
        //SplashScreen.installSplashScreen(this)
        app = application as LuaApplication
        localDir = app.luaDir
//        try {
//            if (File(app!!.getLuaPath("setup.png")).exists())
//                window.setBackgroundDrawable(
//                    BitmapDrawable(
//                        resources,
//                        app!!.getLuaPath("setup.png")
//                    )
//                )
//        } catch (e: Exception) {
//            e.printStackTrace();
//        }
        if (checkInfo()) {
            LuaApplication.getInstance().setSharedData("UnZiped", false)
            //Log.i("start execute", "welcome");
            lifecycleScope.launch(Dispatchers.IO) {
                try {
                    //Log.i("start unpack", "welcome");
                    unApk("assets/", localDir)
                } catch (e: IOException) {
                    e.printStackTrace()
                }
                withContext(Dispatchers.Main) {
                    //Log.i("start", "welcome");
                    startActivity()
                    LuaApplication.getInstance().setSharedData("UnZiped", true)
                }
            }
        } else {
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
                val edit = info.edit()
                edit.putString("versionName", versionName)
                edit.apply()
                isVersionChanged = true
            }
            val oldLastTime = info.getLong("lastUpdateTime", 0)
            if (oldLastTime != lastTime) {
                val edit = info.edit()
                edit.putLong("lastUpdateTime", lastTime)
                edit.apply()
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

    /*
  private void unApk(String dir, String extDir) throws ZipException {
    File file = new File(extDir);
    String tempDir = getCacheDir().getPath();
    rmDir(file);
    ZipFile zipFile = new ZipFile(getApplicationInfo().publicSourceDir);
    zipFile.extractFile(dir, tempDir);
    new File(tempDir + "/" + dir).renameTo(file);
  }

  private void rmDir(File file, String str) {
    if (file.isDirectory()) {
      for (File file2 : file.listFiles()) {
        rmDir(file2, str);
      }
      file.delete();
    }
    if (file.getName().endsWith(str)) {
      file.delete();
    }
  }

  private boolean rmDir(File file) {
    if (file.isDirectory()) {
      for (File file2 : file.listFiles()) {
        rmDir(file2);
      }
    }
    return file.delete();
  }
  */
    private var zipFile: ZipFile? = null
    private var destPath: String? = null

    @Throws(IOException::class)
    fun unApk(dir: String, extDir: String?) {
        val dirtest = ArrayList<String>()
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
                dirtest.add(fp + File.separator)
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
            val watchiter: Iterator<String> = dirtest.iterator()
            var find = false
            while (watchiter.hasNext()) {
                val dirtestwatchn = watchiter.next()
                if (fp.startsWith(dirtestwatchn)) {
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

    private inner class FileWritingTask internal constructor(
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
            if (parentFile.isDirectory) {
                try {
                    val inputStream = zipFile!!.getInputStream(zipEntry)
                    val outputStream: OutputStream = FileOutputStream(file)
                    val buffer = ByteArray(2048)
                    var n: Int
                    while (inputStream.read(buffer).also { n = it } >= 0) {
                        outputStream.write(buffer, 0, n)
                    }
                    outputStream.close()
                } catch (e: IOException) {
                    e.printStackTrace()
                    throw RuntimeException("unzip error at file " + file.absolutePath + ".")
                }
            } else {
                throw RuntimeException(
                    "ParentFile( path = \""
                            + parentFile.absolutePath
                            + "\" ) is not a directory, the application can't write the File( name = \""
                            + file.name
                            + "\" ) in a file."
                )
            }
        }
    }
}

package com.androlua

import android.app.Application
import android.content.Context
import android.os.Environment
import androidx.preference.PreferenceManager
import com.nekolaska.internal.commit
import org.luaj.Globals
import org.luaj.LuaTable
import java.io.File
import java.io.FileInputStream

/**
 * Created by nirenr on 2019/12/13.
 */
class LuaApplication : Application(), LuaContext {
    private var mExtDir: String? = null
    override fun onCreate() {
        super.onCreate()
        instance = this
        getExternalFilesDir("dexfiles")?.let { rmDir(it) }
        CrashHandler.instance.init(this)
        //DynamicColors.applyToActivitiesIfAvailable(this)
        //EmulatorSDK.init(this)
    }

    override fun getClassLoaders(): ArrayList<ClassLoader>? {
        return null
    }

    override fun call(func: String, vararg args: Any) {
    }

    override fun set(name: String, value: Any) {
    }

    override fun getLuaPath(): String {
        return filesDir.absolutePath
    }

    override fun getLuaPath(s: String): String {
        return filesDir.resolve(s).absolutePath
    }

    override fun getLuaPath(dir: String, name: String): String? {
        return filesDir.resolve(dir).resolve(name).absolutePath
    }

    override fun getLuaDir(): String {
        return filesDir.absolutePath
    }

    override fun getLuaDir(dir: String): String? {
        return filesDir.resolve(dir).absolutePath
    }

    override fun getLuaExtDir(): String {
        if (mExtDir != null) return mExtDir as String
        val d = File(Environment.getExternalStorageDirectory(), "LuaJ")
        if (!d.exists()) d.mkdirs()
        mExtDir = d.absolutePath
        return mExtDir as String
    }

    override fun getLuaExtDir(dir: String): String {
        val d = File(luaExtDir, dir)
        if (!d.exists()) d.mkdirs()
        return d.absolutePath
    }

    override fun setLuaExtDir(dir: String) {
        mExtDir = dir
    }

    override fun getLuaExtPath(path: String): String {
        return File(luaExtDir, path).absolutePath
    }

    override fun getLuaExtPath(dir: String, name: String): String {
        return File(getLuaExtDir(dir), name).absolutePath
    }

    override fun getContext(): Context {
        return this
    }

    override fun getLuaState(): Globals? {
        return null
    }

    override fun doFile(path: String, vararg arg: Any): Any? {
        return null
    }

    override fun sendMsg(msg: String) {
    }

    override fun sendError(title: String, msg: Exception) {
    }

    override fun getWidth(): Int {
        return 0
    }

    override fun getHeight(): Int {
        return 0
    }

    override fun getGlobalData(): Map<*, *> {
        return sGlobalData
    }

    override fun getSharedData(): Map<String, *> {
        return PreferenceManager.getDefaultSharedPreferences(this).all
    }

    override fun getSharedData(key: String): Any {
        return PreferenceManager.getDefaultSharedPreferences(this).all[key]!!
    }

    override fun getSharedData(key: String, def: Any): Any {
        val ret = PreferenceManager.getDefaultSharedPreferences(this).all[key]
        if (ret != null) return ret
        return def
    }

    @Suppress("UNCHECKED_CAST")
    override fun setSharedData(key: String, value: Any?): Boolean {
        return PreferenceManager.getDefaultSharedPreferences(this).commit {
            if (value == null)
                remove(key)
            else when (value.javaClass.simpleName) {
                "String" -> putString(key, value as String)
                "Long" -> putLong(key, (value as Long))
                "Integer" -> putInt(key, (value as Int))
                "Float" -> putFloat(key, (value as Float))
                "LuaTable" -> putString(
                    key,
                    (value as LuaTable).values().toString()
                )

                "Set" -> putStringSet(key, value as Set<String>)
                "Boolean" -> putBoolean(key, (value as Boolean))
                else -> return false
            }
        }
    }


    override fun regGc(obj: LuaGcable) {
    }

    override fun findResource(name: String): FileInputStream? {
        try {
            if (File(name).exists()) return FileInputStream(name)
        } catch (_: Exception) {
            /*
      e.printStackTrace();*/
        }
        try {
            return FileInputStream(getLuaPath(name))
        } catch (_: Exception) {
            /*
      e.printStackTrace();*
        }
        try {
            return getAssets().open(name);
        } catch (Exception ioe) {
      / *
      e.printStackTrace();*/
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
            val `in` = assets.open(name)
            `in`.close()
            return true
        } catch (_: Exception) {
        }
        return false
    }

    override fun findFile(filename: String): String {
        if (filename.startsWith("/")) return filename
        return getLuaPath(filename)
    }


    companion object {
        @JvmStatic
        lateinit var instance: LuaApplication

        private val sGlobalData: HashMap<*, *> = HashMap<Any?, Any?>()

        fun rmDir(dir: File): Boolean {
            if (dir.isDirectory) {
                for (f in dir.listFiles()!!) rmDir(f)
            }
            return dir.delete()
        }
    }
}

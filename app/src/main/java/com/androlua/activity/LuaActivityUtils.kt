package com.androlua.activity

import android.content.pm.PackageManager
import android.os.StrictMode
import androidx.core.util.TypedValueCompat
import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaBackPressedCallback
import kotlinx.coroutines.launch
import org.luaj.LuaFunction
import org.luaj.LuaValue
import kotlin.system.measureTimeMillis

class LuaActivityUtils(private val activity: LuaActivity) {
    
    fun setAllowThread(bool: Boolean) {
        val policy = if (bool) {
            StrictMode.ThreadPolicy.Builder().permitAll().build()
        } else {
            StrictMode.ThreadPolicy.Builder().detectAll().build()
        }
        StrictMode.setThreadPolicy(policy)
    }
    
    fun dpToPx(dp: Float): Float {
        return TypedValueCompat.dpToPx(dp, activity.resources.displayMetrics)
    }
    
    fun spToPx(sp: Float): Float {
        return TypedValueCompat.spToPx(sp, activity.resources.displayMetrics)
    }
    
    fun addOnBackPressedCallback(callback: LuaFunction) {
        activity.onBackPressedDispatcher.addCallback(LuaBackPressedCallback(callback))
    }
    
    fun delay(time: Long, callback: LuaValue) = activity.lifecycleScope.launch {
        kotlinx.coroutines.delay(time)
        runCatching { callback.call() }.onFailure { activity.sendError("delay", it as Exception) }
    }
    
    fun measureTime(action: LuaValue) = measureTimeMillis {
        action.call()
    }
    
    fun getVersionName(default: String): String {
        return try {
            activity.packageManager.getPackageInfo(activity.packageName, 0).versionName ?: default
        } catch (e: PackageManager.NameNotFoundException) {
            default
        }
    }
}
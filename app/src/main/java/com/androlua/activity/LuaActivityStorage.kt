package com.androlua.activity

import androidx.preference.PreferenceManager
import com.androlua.LuaActivity
import com.androlua.LuaApplication
import com.nekolaska.internal.commit
import org.luaj.LuaTable

class LuaActivityStorage(private val activity: LuaActivity) {
    
    fun getGlobalData(): Map<*, *> {
        return LuaApplication.instance.globalData
    }
    
    fun getSharedData(): MutableMap<String?, *>? {
        return PreferenceManager.getDefaultSharedPreferences(activity).all
    }
    
    fun getSharedData(key: String?): Any? {
        return PreferenceManager.getDefaultSharedPreferences(activity).all[key]
    }
    
    fun getSharedData(key: String?, default: Any?): Any? {
        return PreferenceManager.getDefaultSharedPreferences(activity).all[key] ?: default
    }
    
    @Suppress("UNCHECKED_CAST")
    fun setSharedData(key: String?, value: Any?): Boolean {
        return PreferenceManager.getDefaultSharedPreferences(activity).commit {
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
}
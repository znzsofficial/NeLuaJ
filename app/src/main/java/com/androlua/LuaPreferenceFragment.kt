package com.androlua

import android.os.Bundle
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.lib.jse.CoerceJavaToLua

/**
 * Created by Administrator on 2018/08/05 0005.
 */
class LuaPreferenceFragment(private var mPreferences: LuaTable) : PreferenceFragmentCompat(),
    Preference.OnPreferenceChangeListener,
    Preference.OnPreferenceClickListener {
    private var mOnPreferenceChangeListener: Preference.OnPreferenceChangeListener? = null
    private var mOnPreferenceClickListener: Preference.OnPreferenceClickListener? = null

    override fun onCreatePreferences(bundle: Bundle?, s: String?) {
        preferenceScreen = preferenceManager.createPreferenceScreen(requireActivity())
        try {
            init(mPreferences)
        } catch (e: Exception) {
            LuaActivity.logError("LuaPreferenceFragment", e)
        }
    }

    fun setPreference(preferences: LuaTable) {
        mPreferences = preferences
    }

    private fun init(preferences: LuaTable) {
        val ps = preferenceScreen
        val len = preferences.length()
        for (i in 1..len) {
            val p = preferences[i].checktable()
            try {
                val cls = p[1]
                require(!cls.isnil()) { "First value Must be a Class<Preference>, checked import package." }
                val pf = cls.jcall(activity) as Preference
                pf.onPreferenceChangeListener = this
                pf.onPreferenceClickListener = this
                val ks = p.keys()
                for (et in ks) {
                    if (et.isstring()) {
                        try {
                            CoerceJavaToLua.coerce(pf).jset(et.tojstring(), p[et])
                        } catch (e: LuaError) {
                            e.printStackTrace()
                        }
                    }
                }
                ps.addPreference(pf)
            } catch (e: Exception) {
                LuaActivity.logError("LuaPreferenceFragment", e)
            }
        }
    }

    fun setOnPreferenceChangeListener(listener: Preference.OnPreferenceChangeListener?) {
        mOnPreferenceChangeListener = listener
    }

    fun setOnPreferenceClickListener(listener: Preference.OnPreferenceClickListener?) {
        mOnPreferenceClickListener = listener
    }

    override fun onPreferenceChange(preference: Preference, newValue: Any): Boolean {
        if (mOnPreferenceChangeListener != null) return mOnPreferenceChangeListener!!.onPreferenceChange(
            preference,
            newValue
        )
        return true
    }

    override fun onPreferenceClick(preference: Preference): Boolean {
        if (mOnPreferenceClickListener != null) return mOnPreferenceClickListener!!.onPreferenceClick(
            preference
        )
        return false
    }
}
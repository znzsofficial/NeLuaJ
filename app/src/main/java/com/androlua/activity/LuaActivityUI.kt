package com.androlua.activity

import android.content.ClipData
import android.content.ClipboardManager
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import com.androlua.LuaActivity
import com.androlua.LuaLayout
import com.androlua.adapter.ArrayListAdapter
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.MaterialColors
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable
import java.io.File

class LuaActivityUI(private val activity: LuaActivity) {
    
    private val toastBuilder = StringBuilder()
    private var toast: Toast? = null
    private var lastShow: Long = 0
    private var toastTextView: TextView? = null
    
    fun setContentView(view: LuaTable) {
        activity.setContentView(LuaLayout(activity).load(view, activity.globals).touserdata(android.view.View::class.java))
    }
    
    fun setContentView(view: LuaTable, env: LuaTable) {
        activity.setContentView(LuaLayout(activity).load(view, env).touserdata(android.view.View::class.java))
    }
    
    fun setFragment(fragment: Fragment) {
        activity.setContentView(android.view.View(activity))
        activity.supportFragmentManager.beginTransaction().replace(android.R.id.content, fragment)
            .commit()
    }
    
    fun showLogView(isError: Boolean) {
        activity.setTheme(R.style.Theme_NeLuaJ_Material3_DynamicColors_NoActionBar)
        activity.supportActionBar?.hide()
        DynamicColors.applyToActivityIfAvailable(activity)
        activity.setContentView(R.layout.log_list)
        
        val surfaceColor = MaterialColors.getColor(activity, com.google.android.material.R.attr.colorSurface, "LogView")
        activity.findViewById<View>(android.R.id.content)?.setBackgroundColor(surfaceColor)
        activity.window.statusBarColor = surfaceColor
        activity.window.navigationBarColor = surfaceColor
        val systemUiFlags = if (MaterialColors.isColorLight(surfaceColor)) {
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        } else {
            View.SYSTEM_UI_FLAG_VISIBLE
        }
        activity.window.decorView.systemUiVisibility = systemUiFlags
        
        val toolbar = activity.findViewById<com.google.android.material.appbar.MaterialToolbar>(R.id.log_toolbar)
        toolbar.title = File(activity.luaFile).name
        toolbar.subtitle = if (isError) "Runtime Error" else "Log"
        toolbar.setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material)
        toolbar.setNavigationOnClickListener { activity.finish() }
        toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_copy -> {
                    val clipboard = ContextCompat.getSystemService(activity, ClipboardManager::class.java)
                    val clip = ClipData.newPlainText("log", buildString {
                        for (i in 0 until activity.logAdapter.count) {
                            append(activity.logAdapter.getItem(i))
                            if (i < activity.logAdapter.count - 1) append("\n")
                        }
                    })
                    clipboard?.setPrimaryClip(clip)
                    true
                }
                R.id.action_clear -> {
                    activity.logAdapter.clear()
                    true
                }
                else -> false
            }
        }
        
        val recyclerView = activity.findViewById<androidx.recyclerview.widget.RecyclerView>(R.id.log_list)
        recyclerView.layoutManager = androidx.recyclerview.widget.LinearLayoutManager(activity)
        recyclerView.adapter = activity.logAdapter
        // 滚动到最新日志
        if (activity.logAdapter.count > 0) {
            recyclerView.scrollToPosition(activity.logAdapter.count - 1)
        }
    }
    
    fun showLogs() {
        MaterialAlertDialogBuilder(activity)
            .setTitle("Logs")
            .setAdapter(ArrayListAdapter(activity, LuaActivity.logs), null)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }
    
    fun showToast(text: String?) {
        if (!activity.debug) return
        val now = System.currentTimeMillis()
        
        // 2. 判断是创建新 Toast 还是更新现有 Toast
        if (toast == null || toastTextView == null || now - lastShow > 2000) { // 延长一点间隔时间，体验更好
            // --- 创建一个新的 Toast ---
            
            // 重置 StringBuilder
            toastBuilder.setLength(0)
            toastBuilder.append(text)
            
            // 加载自定义布局
            val inflater = LayoutInflater.from(activity)
            val layout = inflater.inflate(R.layout.toast_layout, null)
            
            // 找到 TextView 并设置文本
            toastTextView = layout.findViewById(R.id.toast_text)
            toastTextView?.text = toastBuilder.toString()
            
            // 创建 Toast 实例并设置自定义视图
            toast = Toast(activity).apply {
                duration = Toast.LENGTH_LONG
                view = layout
            }
            toast?.show()
            
        } else {
            // --- 更新现有的 Toast ---
            
            // 追加新内容
            toastBuilder.append("\n")
            toastBuilder.append(text)
            
            // 直接更新 TextView 的文本
            toastTextView?.text = toastBuilder.toString()
            
            // 重新设置时长并再次显示，这会重置 Toast 的显示计时器
            toast?.duration = Toast.LENGTH_LONG
            toast?.show()
        }
        
        // 3. 更新最后显示时间
        lastShow = now
    }
    
    fun getDecorView(): ViewGroup {
        return activity.window.decorView as ViewGroup
    }
    
    fun getRootView(): ViewGroup {
        return activity.window.decorView.rootView as ViewGroup
    }
}
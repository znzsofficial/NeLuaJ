package com.androlua

import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.FrameLayout
import android.widget.ScrollView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.textview.MaterialTextView

/**
 * @ClassName UncaughtExceptionActivity
 * @Description 异常页面
 * @Author summerain0
 * @Date 2020/9/12 11:02
 */
class UncaughtExceptionActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 读取日志，显示在屏幕上
        val msg = intent.getStringExtra("error")
        val scrollView = ScrollView(this) // 防止日志太长看不完
        scrollView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        val textView = MaterialTextView(this)
        textView.text = msg
        scrollView.addView(textView)
        setContentView(scrollView)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 0, 0, "重启").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        menu.add(0, 1, 0, android.R.string.copy).setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        return super.onCreateOptionsMenu(menu)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        when (item.itemId) {
            0 -> {
                val intent = Intent(this, LuaActivity::class.java)
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // 请勿修改，否则无法打开页面
                startActivity(intent)
                System.exit(1) // 请勿修改，否则无法打开页面
                val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                cm.text = getIntent().getStringExtra("error")
            }

            1 -> {
                val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                cm.text = intent.getStringExtra("error")
            }
        }
        return true
    }

    companion object {
        const val TAG: String = "UncaughtExceptionActivity"
    }
}
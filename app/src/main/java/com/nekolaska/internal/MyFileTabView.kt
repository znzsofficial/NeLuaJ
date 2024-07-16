package com.nekolaska.internal

import android.content.Context
import android.view.MotionEvent
import github.daisukiKaffuChino.LuaFileTabView

class MyFileTabView(context: Context) : LuaFileTabView(context) {
    override fun onInterceptTouchEvent(event: MotionEvent?): Boolean {
        return true
    }
}
package com.nekolaska.internal

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import github.daisukiKaffuChino.LuaFileTabView

class MyFileTabView(context: Context?, attrs: AttributeSet?) : LuaFileTabView(context, attrs) {
   override fun onInterceptTouchEvent(event: MotionEvent?): Boolean {
       return true
   }
}
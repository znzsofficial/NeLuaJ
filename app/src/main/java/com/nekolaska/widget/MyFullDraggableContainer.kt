package com.nekolaska.widget

import android.content.Context
import android.view.MotionEvent
import com.drakeet.drawer.FullDraggableContainer

class MyFullDraggableContainer(context: Context?) : FullDraggableContainer(context!!) {
    private var isSwipeable = true

    // 重写 onInterceptTouchEvent 方法
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        super.onInterceptTouchEvent(event)
        return if (isSwipeable) {
            onTouchEvent(event)
        } else false
    }

    fun setSwipeable(z: Boolean) {
        isSwipeable = z
    }
}

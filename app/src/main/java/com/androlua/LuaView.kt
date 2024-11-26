package com.androlua

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import org.luaj.LuaValue

class LuaView : FrameLayout {
    constructor(context: Context) : super(context)
    constructor(context: Context, value: LuaValue) : super(context) {
        addView(LuaLayout(context).load(value).touserdata<View?>(View::class.java))
    }
}

package com.androlua

import android.graphics.drawable.Drawable
import coil.target.Target
import org.luaj.LuaValue

class LuaTarget(val view: LuaValue) : Target {

    override fun onSuccess(result: Drawable) {
        super.onSuccess(result)
        view.jset("ImageDrawable", result)
    }
}
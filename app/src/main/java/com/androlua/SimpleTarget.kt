package com.androlua

import android.graphics.drawable.Drawable
import coil.target.Target
import org.luaj.LuaFunction

class SimpleTarget(private val function: LuaFunction) : Target {
    override fun onSuccess(result: Drawable) {
        function.jcall(result)
    }
}
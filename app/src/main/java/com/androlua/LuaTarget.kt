package com.androlua

import android.graphics.drawable.Drawable
import coil.target.Target

class LuaTarget(private val listener: Listener) : Target {
    override fun onStart(placeholder: Drawable?) {
        listener.onStart(placeholder)
    }

    override fun onError(error: Drawable?) {
        listener.onError(error)
    }

    override fun onSuccess(result: Drawable) {
        listener.onSuccess(result)
    }

    interface Listener {
        fun onSuccess(result: Drawable)
        fun onError(error: Drawable?)
        fun onStart(placeholder: Drawable?)
    }
}
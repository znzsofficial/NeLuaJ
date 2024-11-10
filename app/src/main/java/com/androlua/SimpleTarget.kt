package com.androlua

import android.app.Activity
import android.graphics.drawable.Drawable
import coil3.BitmapImage
import coil3.Image
import coil3.asDrawable
import coil3.target.Target
import org.luaj.LuaFunction

class SimpleTarget(private val activity: Activity, private val function: LuaFunction) : Target {
    override fun onSuccess(result: Image) {
        function.jcall(result.asDrawable(activity.resources))
    }
}

class LuaTarget(private val activity: Activity, private val listener: Listener) : Target {
    override fun onSuccess(result: Image) {
        listener.onSuccess(result.asDrawable(activity.resources))
    }

    override fun onStart(placeholder: Image?) {
        listener.onStart(placeholder)
    }

    override fun onError(error: Image?) {
        listener.onError(error)
    }

    interface Listener {
        fun onSuccess(result: Drawable)
        fun onStart(image: Image?)
        fun onError(image: Image?)
    }
}
package com.androlua

import android.graphics.drawable.Drawable
import coil3.Image
import coil3.asDrawable
import coil3.target.Target
import coil3.toBitmap
import org.luaj.LuaFunction

class SimpleTarget(private val activity: LuaActivity, private val function: LuaFunction) : Target {
    override fun onSuccess(result: Image) {
        runCatching {
            function.jcall(result.asDrawable(activity.resources))
        }.onFailure { activity.sendError("SimpleTarget", it as Exception) }
    }
}

class BitmapTarget(private val activity: LuaActivity, private val function: LuaFunction) : Target {
    override fun onSuccess(result: Image) {
        runCatching {
            function.jcall(result.toBitmap())
        }.onFailure { activity.sendError("onSuccess", it as Exception) }
    }
}

class LuaTarget(private val activity: LuaActivity, private val listener: Listener) : Target {
    override fun onSuccess(result: Image) {
        runCatching {
            listener.onSuccess(result.asDrawable(activity.resources))
        }.onFailure { activity.sendError("onSuccess", it as Exception) }
    }

    override fun onStart(placeholder: Image?) {
        runCatching {
            listener.onStart(placeholder)
        }.onFailure { activity.sendError("onStart", it as Exception) }
    }

    override fun onError(error: Image?) {
        runCatching {
            listener.onError(error)
        }.onFailure { activity.sendError("onError", it as Exception) }
    }

    interface Listener {
        fun onSuccess(result: Drawable)
        fun onStart(image: Image?)
        fun onError(image: Image?)
    }
}
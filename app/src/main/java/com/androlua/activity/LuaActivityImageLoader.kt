package com.androlua.activity

import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.widget.ImageView
import coil3.ImageLoader
import coil3.asDrawable
import coil3.executeBlocking
import coil3.imageLoader
import coil3.load
import coil3.request.ImageRequest
import coil3.request.crossfade
import coil3.toBitmap
import com.androlua.BitmapTarget
import com.androlua.LuaActivity
import com.androlua.SimpleTarget
import org.luaj.LuaFunction

class LuaActivityImageLoader(private val activity: LuaActivity) {
    
    fun getImageLoader(): ImageLoader {
        return activity.imageLoader
    }
    
    fun syncLoadBitmap(data: Any?): Bitmap? {
        val request = ImageRequest.Builder(activity)
            .data(data)
            .build()
        val result = activity.imageLoader.executeBlocking(request)
        return result.image?.toBitmap()
    }
    
    fun syncLoadDrawable(data: Any?): Drawable? {
        val request = ImageRequest.Builder(activity)
            .data(data)
            .build()
        val result = activity.imageLoader.executeBlocking(request)
        return result.image?.asDrawable(activity.resources)
    }
    
    fun loadBitmap(data: Any?, callback: LuaFunction) =
        activity.imageLoader.enqueue(
            ImageRequest.Builder(activity)
                .data(data)
                .target(BitmapTarget(activity, callback))
                .build()
        )
    
    fun loadImage(data: Any?, callback: LuaFunction) =
        activity.imageLoader.enqueue(
            ImageRequest.Builder(activity)
                .data(data)
                .target(SimpleTarget(activity, callback))
                .build()
        )
    
    fun loadImage(data: Any?, view: ImageView) = view.load(data)
    
    fun loadImageWithCrossFade(data: Any?, view: ImageView) = view.load(data) {
        crossfade(true)
    }
}
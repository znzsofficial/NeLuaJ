package com.androlua.adapter

import android.content.Context
import android.graphics.drawable.Drawable
import android.widget.ImageView
import coil3.ImageLoader
import coil3.asDrawable
import coil3.executeBlocking
import coil3.request.ImageRequest
import coil3.target.ImageViewTarget
import kotlinx.coroutines.Dispatchers

object AsyncLoader {
    fun getDrawable(context: Context, loader: ImageLoader, src: String): Drawable? {
        return loader.executeBlocking(
            ImageRequest.Builder(context)
                .coroutineContext(Dispatchers.Main.immediate)
                .data(src)
                .build()
        ).image?.asDrawable(context.resources)
    }

    fun loadImage(context: Context, loader: ImageLoader, src: Any, view: ImageView) {
        loader.enqueue(
            ImageRequest.Builder(context)
                .data(src)
                .target(ImageViewTarget((view)))
                .build()
        )
    }
}
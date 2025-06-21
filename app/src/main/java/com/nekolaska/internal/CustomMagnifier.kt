package com.nekolaska.internal

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.cardview.widget.CardView
import androidx.core.util.TypedValueCompat
import androidx.core.graphics.createBitmap

class CustomMagnifier(private val sourceView: View) {
    private val context = sourceView.context
    private val displayMetrics = context.resources.displayMetrics
    private val mainHandler = Handler(Looper.getMainLooper())

    // The window is required for PixelCopy
    private val window: Window? = (context as Activity).window
    // UI Elements
    private val magnifierCard: CardView
    private val magnifierImage: AppCompatImageView

    // The root view to which the magnifier will be added as an overlay.
    private val parentView = sourceView.rootView as? ViewGroup

    // Properties
    private var lastBitmap: Bitmap? = null
    private var lastSourceCenterX = 0f
    private var lastSourceCenterY = 0f

    // Configurable dimensions and style
    var zoom: Float = 1.25f
    var cornerRadius: Float
        get() = magnifierCard.radius
        set(value) {
            magnifierCard.radius = value
        }
    var elevationInDp: Float = 4.0f
        set(value) {
            field = value
            magnifierCard.cardElevation = TypedValueCompat.dpToPx(value,displayMetrics)
        }

    private var magnifierWidth = TypedValueCompat.dpToPx(100.0f,displayMetrics)
    private var magnifierHeight = TypedValueCompat.dpToPx(48.0f,displayMetrics)
    private var verticalOffset = TypedValueCompat.dpToPx(-42.0f,displayMetrics)

    init {
        // Fail fast if the magnifier cannot be created.
        if (window == null) {
            throw IllegalStateException("The source view's context is not an Activity or it has no window.")
        }
        if (parentView == null) {
            throw IllegalStateException("The source view is not attached to a window, or its root view is not a ViewGroup.")
        }

        magnifierImage = AppCompatImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_XY
        }

        magnifierCard = CardView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                magnifierWidth.toInt(),
                magnifierHeight.toInt()
            )
            radius = TypedValueCompat.dpToPx(16f,displayMetrics) // Default corner radius
            cardElevation = TypedValueCompat.dpToPx(elevationInDp,displayMetrics)
            visibility = View.GONE
            addView(magnifierImage)
        }

        // Add the magnifier to the top-level container
        parentView.addView(magnifierCard)
    }

    @JvmOverloads
    fun show(
        sourceX: Float,
        sourceY: Float,
        destinationX: Float = sourceX,
        destinationY: Float = sourceY + verticalOffset
    ) {
        if (parentView == null) return

        lastSourceCenterX = sourceX
        lastSourceCenterY = sourceY

        val location = IntArray(2)
        sourceView.getLocationInWindow(location)

        val cardX = (location[0] + destinationX - magnifierWidth / 2.0f).coerceIn(0f, (parentView.width - magnifierWidth))
        val cardY = (location[1] + destinationY - magnifierHeight / 2.0f).coerceIn(0f, (parentView.height - magnifierHeight))

        magnifierCard.x = cardX
        magnifierCard.y = cardY

        if (magnifierCard.visibility != View.VISIBLE) {
            magnifierCard.visibility = View.VISIBLE
        }
        update()
    }

    fun dismiss() {
        magnifierCard.visibility = View.GONE
        lastBitmap?.recycle()
        lastBitmap = null
    }

    fun setDimensions(width: Float, height: Float) {
        magnifierWidth = width
        magnifierHeight = height
        magnifierCard.layoutParams.width = width.toInt()
        magnifierCard.layoutParams.height = height.toInt()
        magnifierCard.requestLayout()
    }

    private fun update() {
        // If window is null, we cannot perform the copy.
        // The init block should prevent this, but it's good practice to check.
        val window = this.window ?: return

        val srcWidth = (magnifierWidth / zoom)
        val srcHeight = (magnifierHeight / zoom)

        val srcLeft = lastSourceCenterX - srcWidth / 2f
        val srcTop = lastSourceCenterY - srcHeight / 2f

        val viewLocation = IntArray(2)
        sourceView.getLocationInWindow(viewLocation)

        val srcRect = Rect(
            (viewLocation[0] + srcLeft).toInt(),
            (viewLocation[1] + srcTop).toInt(),
            (viewLocation[0] + srcLeft + srcWidth).toInt(),
            (viewLocation[1] + srcTop + srcHeight).toInt()
        )

        // Ensure source rectangle has a non-zero size
        if (srcRect.width() <= 0 || srcRect.height() <= 0) {
            return
        }

        val bitmap = createBitmap(srcRect.width(), srcRect.height())

        PixelCopy.request(window, srcRect, bitmap, { result ->
            if (result == PixelCopy.SUCCESS) {
                mainHandler.post {
                    lastBitmap?.recycle()
                    lastBitmap = bitmap
                    magnifierImage.setImageBitmap(lastBitmap)
                }
            } else {
                bitmap.recycle()
            }
        }, mainHandler)
    }
}
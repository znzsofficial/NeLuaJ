package com.nekolaska.internal

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.cardview.widget.CardView
import androidx.core.graphics.createBitmap
import androidx.core.util.TypedValueCompat

class CustomMagnifier(private val sourceView: View) {
    private val context = sourceView.context
    private val displayMetrics = context.resources.displayMetrics
    private val mainHandler = Handler(Looper.getMainLooper())
    private val parentView = sourceView.rootView as? ViewGroup
        ?: throw IllegalStateException("The source view is not attached to a window.")

    private val magnifierImage = AppCompatImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_XY
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val magnifierCard: CardView
    private val copyRunnable = Runnable {
        copyScheduled = false
        if (!destroyed && magnifierCard.visibility == View.VISIBLE) copyContent()
    }

    private var copyBitmap: Bitmap? = null
    private var lastSourceCenterX = 0f
    private var lastSourceCenterY = 0f
    private var copyScheduled = false
    private var destroyed = false

    var zoom: Float = 1.25f
        set(value) {
            field = value.coerceAtLeast(1f)
        }
    var cornerRadius: Float
        get() = magnifierCard.radius
        set(value) {
            magnifierCard.radius = value
        }

    fun setCornerRadius(radius: Float): CustomMagnifier {
        magnifierCard.radius = radius
        return this
    }

    var elevationInDp: Float = 4.0f
        set(value) {
            field = value
            magnifierCard.cardElevation = TypedValueCompat.dpToPx(value, displayMetrics)
        }

    private var magnifierWidth = TypedValueCompat.dpToPx(130.0f, displayMetrics)
    private var magnifierHeight = TypedValueCompat.dpToPx(56.0f, displayMetrics)
    private var verticalOffset = TypedValueCompat.dpToPx(-52.0f, displayMetrics)

    init {
        magnifierCard = CardView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                magnifierWidth.toInt(),
                magnifierHeight.toInt()
            )
            radius = TypedValueCompat.dpToPx(16f, displayMetrics)
            cardElevation = TypedValueCompat.dpToPx(elevationInDp, displayMetrics)
            visibility = View.GONE
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            addView(magnifierImage)
        }
        parentView.addView(magnifierCard)
    }

    @JvmOverloads
    fun show(
        sourceX: Float,
        sourceY: Float,
        destinationX: Float = sourceX,
        destinationY: Float = sourceY + verticalOffset
    ) {
        if (destroyed) return

        lastSourceCenterX = sourceX
        lastSourceCenterY = sourceY

        val location = IntArray(2)
        sourceView.getLocationInWindow(location)
        val parentLocation = IntArray(2)
        parentView.getLocationInWindow(parentLocation)
        val relX = location[0] - parentLocation[0]
        val relY = location[1] - parentLocation[1]

        val maxX = (parentView.width - magnifierWidth).coerceAtLeast(0f)
        val maxY = (parentView.height - magnifierHeight).coerceAtLeast(0f)
        magnifierCard.x = (relX + destinationX - magnifierWidth / 2.0f).coerceIn(0f, maxX)
        magnifierCard.y = (relY + destinationY - magnifierHeight / 2.0f).coerceIn(0f, maxY)

        val isFirstShow = magnifierCard.visibility != View.VISIBLE
        if (isFirstShow) {
            magnifierCard.visibility = View.VISIBLE
            copyContent()
        } else {
            scheduleCopy()
        }
    }

    fun dismiss() {
        if (destroyed) return
        magnifierCard.visibility = View.GONE
        mainHandler.removeCallbacks(copyRunnable)
        copyScheduled = false
    }

    fun setDimensions(width: Float, height: Float): CustomMagnifier {
        magnifierWidth = width.coerceAtLeast(1f)
        magnifierHeight = height.coerceAtLeast(1f)
        magnifierCard.layoutParams.width = magnifierWidth.toInt()
        magnifierCard.layoutParams.height = magnifierHeight.toInt()
        magnifierCard.requestLayout()
        recycleBitmap()
        if (magnifierCard.visibility == View.VISIBLE) copyContent()
        return this
    }

    fun destroy() {
        if (destroyed) return
        destroyed = true
        dismiss()
        magnifierImage.setImageDrawable(null)
        recycleBitmap()
        (magnifierCard.parent as? ViewGroup)?.removeView(magnifierCard)
    }

    private fun scheduleCopy() {
        if (copyScheduled) return
        copyScheduled = true
        mainHandler.postDelayed(copyRunnable, COPY_INTERVAL_MS)
    }

    private fun copyContent() {
        val viewWidth = sourceView.width
        val viewHeight = sourceView.height
        val outWidth = magnifierWidth.toInt().coerceAtLeast(1)
        val outHeight = magnifierHeight.toInt().coerceAtLeast(1)
        if (viewWidth <= 0 || viewHeight <= 0) return

        val srcWidth = (magnifierWidth / zoom).coerceIn(1f, viewWidth.toFloat())
        val srcHeight = (magnifierHeight / zoom).coerceIn(1f, viewHeight.toFloat())
        val left = (lastSourceCenterX - srcWidth / 2f)
            .coerceIn(0f, (viewWidth - srcWidth).coerceAtLeast(0f))
        val top = (lastSourceCenterY - srcHeight / 2f)
            .coerceIn(0f, (viewHeight - srcHeight).coerceAtLeast(0f))

        val bitmap = obtainBitmap(outWidth, outHeight)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        canvas.save()
        canvas.scale(outWidth / srcWidth, outHeight / srcHeight)
        canvas.translate(-left, -top)
        sourceView.draw(canvas)
        canvas.restore()

        if (magnifierImage.drawable == null) {
            magnifierImage.setImageBitmap(bitmap)
        } else {
            magnifierImage.invalidate()
        }
    }

    private fun obtainBitmap(width: Int, height: Int): Bitmap {
        val current = copyBitmap
        if (current != null &&
            !current.isRecycled &&
            current.width == width &&
            current.height == height
        ) {
            return current
        }
        recycleBitmap()
        return createBitmap(width, height).also { copyBitmap = it }
    }

    private fun recycleBitmap() {
        magnifierImage.setImageDrawable(null)
        copyBitmap?.recycle()
        copyBitmap = null
    }

    companion object {
        private const val COPY_INTERVAL_MS = 16L
    }
}

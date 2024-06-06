package com.nekolaska.widget

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Matrix
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.View
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.cardview.widget.CardView

class CustomMagnifier(private val mView: View) {
    private var imageHeight: Float
    private var imageWidth: Float
    private var lastSourceCenterX = 0f
    private var lastSourceCenterY = 0f
    private val mCardView: CardView
    private val mContext: Activity = mView.context as Activity
    private val mDecorView: FrameLayout
    private val displayMetrics: DisplayMetrics = mContext.resources.displayMetrics
    private val mImageView: AppCompatImageView
    private var mLastBitmap: Bitmap? = null
    private val matrix = Matrix()
    private var zoom = 1.25f
    private val verticalOffset: Float
    private var mElevation = 4.0f

    init {
        mCardView = CardView(mContext)
        mImageView = AppCompatImageView(mContext)
        mCardView.addView(mImageView)
        mCardView.visibility = View.GONE
        // 设置卡片圆角
        mCardView.radius = 16f
        mCardView.cardElevation = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            mElevation,
            displayMetrics
        )
        val decorView = mContext.window.decorView as FrameLayout
        mDecorView = decorView
        decorView.addView(mCardView)
        imageWidth = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 100.0f, displayMetrics)
        imageHeight = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 48.0f, displayMetrics)
        verticalOffset =
            TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, -42.0f, displayMetrics)
        val layoutParams = mCardView.layoutParams
        layoutParams.width = imageWidth.toInt()
        layoutParams.height = imageHeight.toInt()
        mCardView.layoutParams = layoutParams
    }

    private fun cropBitmap(bitmap: Bitmap, x: Int, y: Int, width: Int, height: Int): Bitmap {
        var x = x
        var y = y
        val scale = zoom
        matrix.setScale(scale, scale)
        if (x < 0) {
            x = 0
        } else if (x > bitmap.width - width) {
            x = bitmap.width - width
        }
        if (y < 0) {
            y = 0
        } else if (y > bitmap.height - height) {
            y = bitmap.height - height
        }
        val croppedBitmap = Bitmap.createBitmap(bitmap, x, y, width, height, matrix, true)
        bitmap.recycle()
        return croppedBitmap
    }

    fun dismiss() {
        mCardView.visibility = View.GONE
        val bitmap = mLastBitmap
        bitmap?.recycle()
    }

    fun setDimensions(width: Float, height: Float) {
        imageWidth = width
        imageHeight = height
        val layoutParams = mCardView.layoutParams
        layoutParams.width = imageWidth.toInt()
        layoutParams.height = imageHeight.toInt()
        mCardView.layoutParams = layoutParams
    }

    fun setCornerRadius(radius: Float) {
        mCardView.radius = radius
    }

    @JvmOverloads
    fun show(
        sourceX: Float,
        sourceY: Float,
        destinationX: Float = sourceX,
        destinationY: Float = verticalOffset + sourceY
    ) {
        lastSourceCenterX = sourceX
        lastSourceCenterY = sourceY
        val location = IntArray(2)
        mView.getLocationInWindow(location)
        val viewX = location[0]
        val viewY = location[1]
        val decorViewWidth = mDecorView.measuredWidth
        val decorViewHeight = mDecorView.measuredHeight
        val x = viewX.toFloat()
        val cardWidth = imageWidth
        val cardX = x + destinationX - cardWidth / 2.0f
        val y = viewY.toFloat() + destinationY - imageHeight / 2.0f
        if (cardX < 0.0f) {
            mCardView.x = 0.0f
        } else {
            val rightBoundary = decorViewWidth.toFloat()
            if (cardX > rightBoundary - cardWidth) {
                mCardView.x = rightBoundary - cardWidth
            } else {
                mCardView.x = cardX
            }
        }
        if (y < 0.0f) {
            mCardView.y = 0.0f
        } else {
            val bottomBoundary = decorViewHeight.toFloat()
            val cardHeight = imageHeight
            if (y > bottomBoundary - cardHeight) {
                mCardView.y = bottomBoundary - cardHeight
            } else {
                mCardView.y = y
            }
        }
        mCardView.visibility = View.VISIBLE
        update()
    }

    private fun update() {
        mView.isDrawingCacheEnabled = true
        val viewBitmap = mView.drawingCache.copy(Bitmap.Config.ARGB_8888, true)
        mView.isDrawingCacheEnabled = false
        var width = imageWidth
        var zoom = zoom
        width /= zoom
        zoom = imageHeight / zoom
        val lastBitmap = mLastBitmap
        lastBitmap?.recycle()
        val croppedBitmap = cropBitmap(
            viewBitmap,
            (lastSourceCenterX - width / 2.0f).toInt(),
            (lastSourceCenterY - zoom / 2.0f).toInt(),
            width.toInt(),
            zoom.toInt()
        )
        mLastBitmap = croppedBitmap
        mImageView.setImageBitmap(croppedBitmap)
    }

    var elevation: Float
        get() = mElevation
        set(elevation) {
            mElevation = elevation
            mCardView.cardElevation = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                elevation,
                displayMetrics
            )
        }
}
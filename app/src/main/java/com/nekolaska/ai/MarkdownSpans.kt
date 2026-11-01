package com.nekolaska.ai

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.LeadingMarginSpan
import android.text.style.UpdateAppearance
import androidx.annotation.ColorInt

/**
 * 现代 Markdown 渲染专用 Span 集。
 * 纯原生 Canvas 绘制，零第三方依赖，自适应屏幕密度 (DPI)。
 */

/**
 * 行内代码背景与字体 Span：
 * - 保持字符等宽 (monospace) 并继承原有字体风格（粗体等）
 * - 自带浅色底色
 * - 避免使用累计乘法缩放，防止连续测量时字号漂移
 */
class ModernInlineCodeSpan(
    @ColorInt private val bgColor: Int,
    @ColorInt private val textColor: Int
) : CharacterStyle(), UpdateAppearance {

    override fun updateDrawState(tp: TextPaint) {
        val oldStyle = tp.typeface?.style ?: Typeface.NORMAL
        tp.typeface = Typeface.create(Typeface.MONOSPACE, oldStyle)
        if (textColor != 0) {
            tp.color = textColor
        }
        tp.bgColor = bgColor
    }
}

/**
 * 现代引用条 Span (QuoteSpan)：
 * - 绘制饱满的主题强调色左侧竖条 (平滑连续矩形拼接)
 * - 与正文之间提供舒适的呼吸间距 (gapPx)
 */
class ModernQuoteSpan(
    @ColorInt private val stripeColor: Int,
    private val stripeWidthPx: Float,
    private val gapPx: Float
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int {
        return (stripeWidthPx + gapPx).toInt()
    }

    override fun drawLeadingMargin(
        c: Canvas, p: Paint, x: Int, dir: Int,
        top: Int, baseline: Int, bottom: Int,
        text: CharSequence, start: Int, end: Int,
        first: Boolean, layout: Layout
    ) {
        val oldStyle = p.style
        val oldColor = p.color

        p.style = Paint.Style.FILL
        p.color = stripeColor

        val left = if (dir > 0) x.toFloat() else (x - stripeWidthPx)
        val right = left + stripeWidthPx
        c.drawRect(left, top.toFloat(), right, bottom.toFloat(), p)

        p.style = oldStyle
        p.color = oldColor
    }
}

/**
 * 现代水平分割线 Span：
 * - 替代简陋的 "\u2500" 字符拼接
 * - 根据行宽自适应居中绘制细腻的分割线
 */
class ModernDividerSpan(
    @ColorInt private val dividerColor: Int,
    private val thicknessPx: Float
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int = 0

    override fun drawLeadingMargin(
        c: Canvas, p: Paint, x: Int, dir: Int,
        top: Int, baseline: Int, bottom: Int,
        text: CharSequence, start: Int, end: Int,
        first: Boolean, layout: Layout
    ) {
        val oldStyle = p.style
        val oldColor = p.color
        val oldStroke = p.strokeWidth

        p.style = Paint.Style.STROKE
        p.color = dividerColor
        p.strokeWidth = thicknessPx

        val centerY = (top + bottom) / 2f
        val startX = if (dir > 0) x.toFloat() else (x - layout.width).toFloat()
        val endX = startX + layout.width
        c.drawLine(startX, centerY, endX, centerY, p)

        p.style = oldStyle
        p.color = oldColor
        p.strokeWidth = oldStroke
    }
}

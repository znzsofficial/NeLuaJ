package com.nekolaska.ai

import android.graphics.Typeface
import android.text.Editable
import android.text.Html
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import org.xml.sax.XMLReader
import kotlin.collections.ArrayDeque

/**
 * 现代 Markdown 渲染的 Html.TagHandler：
 * - 具备 DPI 屏幕密度感知，精准管理排版层级。
 * - 使用独立的栈结构 (ArrayDeque) 管理标签位置，将闭合查找时间复杂度从 O(N^2) 降至 O(1)。
 * - 具备严密的边界检查，完美容错流式中断或畸形未闭合标签。
 */
class MarkdownTagHandler @JvmOverloads constructor(
    private val tableBgColor: Int = 0,
    private val hrColor: Int = 0,
    private val codeBgColor: Int = 0,
    private val codeTextColor: Int = 0,
    private val quoteStripeColor: Int = 0,
    private val headingColor: Int = 0,
    private val density: Float = 2.0f
) : Html.TagHandler {

    // 独立的位置栈，替代低效且易错位的全局 getSpans 线性扫描
    private val codeStack = ArrayDeque<Int>()
    private val h1Stack = ArrayDeque<Int>()
    private val h2Stack = ArrayDeque<Int>()
    private val h3Stack = ArrayDeque<Int>()
    private val quoteStack = ArrayDeque<Int>()
    private val tableStack = ArrayDeque<Int>()

    // 根据屏幕密度计算真实像素
    private val stripeWidthPx = 3.5f * density
    private val gapPx = 10f * density
    private val hrThicknessPx = 1.2f * density
    private val tableIndentPx = (10f * density).toInt()

    override fun handleTag(
        opening: Boolean,
        tag: String,
        output: Editable,
        xmlReader: XMLReader
    ) {
        val lowerTag = tag.lowercase()
        when (lowerTag) {
            "m-code" -> {
                if (opening) {
                    codeStack.addLast(output.length)
                } else {
                    val start = codeStack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        output.setSpan(
                            ModernInlineCodeSpan(
                                bgColor = if (codeBgColor != 0) codeBgColor else 0x1A888888,
                                textColor = codeTextColor
                            ),
                            start, output.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                        output.setSpan(
                            RelativeSizeSpan(0.92f),
                            start, output.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                }
            }

            "m-h1" -> {
                if (opening) {
                    h1Stack.addLast(output.length)
                } else {
                    val start = h1Stack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        output.setSpan(RelativeSizeSpan(1.35f), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        output.setSpan(StyleSpan(Typeface.BOLD), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        if (headingColor != 0) {
                            output.setSpan(ForegroundColorSpan(headingColor), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        }
                    }
                }
            }

            "m-h2" -> {
                if (opening) {
                    h2Stack.addLast(output.length)
                } else {
                    val start = h2Stack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        output.setSpan(RelativeSizeSpan(1.2f), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        output.setSpan(StyleSpan(Typeface.BOLD), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        if (headingColor != 0) {
                            output.setSpan(ForegroundColorSpan(headingColor), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        }
                    }
                }
            }

            "m-h3" -> {
                if (opening) {
                    h3Stack.addLast(output.length)
                } else {
                    val start = h3Stack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        output.setSpan(RelativeSizeSpan(1.1f), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        output.setSpan(StyleSpan(Typeface.BOLD), start, output.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                }
            }

            "m-quote" -> {
                if (opening) {
                    quoteStack.addLast(output.length)
                } else {
                    val start = quoteStack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        output.setSpan(
                            ModernQuoteSpan(
                                stripeColor = if (quoteStripeColor != 0) quoteStripeColor else 0xFF888888.toInt(),
                                stripeWidthPx = stripeWidthPx,
                                gapPx = gapPx
                            ),
                            start, output.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                }
            }

            "m-hr", "hr" -> {
                if (opening) {
                    if (output.isNotEmpty() && output.last() != '\n') {
                        output.append("\n")
                    }
                    val pos = output.length
                    output.append(" \n")
                    output.setSpan(
                        ModernDividerSpan(
                            dividerColor = if (hrColor != 0) hrColor else 0x33888888,
                            thicknessPx = hrThicknessPx
                        ),
                        pos, pos + 1,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }

            "table" -> {
                if (opening) {
                    if (output.isNotEmpty() && output.last() != '\n') {
                        output.append("\n")
                    }
                    tableStack.addLast(output.length)
                } else {
                    val start = tableStack.removeLastOrNull() ?: return
                    if (start in 0 until output.length) {
                        if (tableBgColor != 0) {
                            output.setSpan(
                                BackgroundColorSpan(tableBgColor),
                                start, output.length,
                                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                            )
                        }
                        output.setSpan(
                            LeadingMarginSpan.Standard(tableIndentPx),
                            start, output.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                }
            }

            "tr" -> if (opening) output.append("\n")
            "td", "th" -> if (!opening) output.append("   ")
        }
    }
}

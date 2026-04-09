package com.nekolaska.widget

import android.content.Context
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.AttributeSet
import android.util.TypedValue
import com.google.android.material.color.MaterialColors
import com.google.android.material.textview.MaterialTextView
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.MarkwonConfiguration
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.core.spans.CodeBlockSpan
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import io.noties.markwon.ext.tables.TablePlugin
import io.noties.markwon.html.HtmlPlugin
import io.noties.markwon.linkify.LinkifyPlugin
import io.noties.markwon.syntax.SyntaxHighlight

/**
 * 基于 Markwon 的 Markdown 渲染 TextView。
 * 支持 MD3 主题色、代码块美化、Lua 关键字高亮。
 */
class MarkwonTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : MaterialTextView(context, attrs, defStyleAttr) {

    // MD3 主题色
    private val colorPrimary = MaterialColors.getColor(this, androidx.appcompat.R.attr.colorPrimary)
    private val colorOnSurface = MaterialColors.getColor(this, com.google.android.material.R.attr.colorOnSurface)
    private val colorOnSurfaceVariant = MaterialColors.getColor(this, com.google.android.material.R.attr.colorOnSurfaceVariant)
    private val colorSurfaceContainerHighest = MaterialColors.getColor(this, com.google.android.material.R.attr.colorSurfaceContainerHighest)
    private val colorOutlineVariant = MaterialColors.getColor(this, com.google.android.material.R.attr.colorOutlineVariant)

    // Lua 语法高亮色
    private val colorKeyword = colorPrimary
    private val colorString = MaterialColors.getColor(this, com.google.android.material.R.attr.colorTertiary)
    private val colorComment = colorOnSurfaceVariant
    private val colorNumber = MaterialColors.getColor(this, com.google.android.material.R.attr.colorSecondary)
    private val colorBuiltin = MaterialColors.getColor(this, androidx.appcompat.R.attr.colorError)

    private val markwon: Markwon = Markwon.builder(context)
        .usePlugin(HtmlPlugin.create())
        .usePlugin(LinkifyPlugin.create())
        .usePlugin(TablePlugin.create(context))
        .usePlugin(StrikethroughPlugin.create())
        .usePlugin(object : AbstractMarkwonPlugin() {
            override fun configureTheme(builder: MarkwonTheme.Builder) {
                builder
                    .codeTextColor(colorOnSurface)
                    .codeBackgroundColor(colorSurfaceContainerHighest)
                    .codeBlockTextColor(colorOnSurface)
                    .codeBlockBackgroundColor(colorSurfaceContainerHighest)
                    .codeTypeface(Typeface.MONOSPACE)
                    .codeBlockTypeface(Typeface.MONOSPACE)
                    .codeTextSize(spToPx(13f).toInt())
                    .codeBlockMargin(dpToPx(8f).toInt())
                    .headingTextSizeMultipliers(floatArrayOf(1.6f, 1.35f, 1.17f, 1.0f, 0.87f, 0.8f))
                    .headingBreakHeight(0)
                    .thematicBreakColor(colorOutlineVariant)
                    .thematicBreakHeight(dpToPx(1f).toInt())
                    .linkColor(colorPrimary)
                    .blockQuoteColor(colorPrimary)
                    .blockQuoteWidth(dpToPx(3f).toInt())
                    .blockMargin(dpToPx(16f).toInt())
                    .bulletWidth(dpToPx(4f).toInt())
                    .listItemColor(colorOnSurface)
            }

            override fun configureConfiguration(builder: MarkwonConfiguration.Builder) {
                // 通过 Markwon 的 SyntaxHighlight 接口实现代码块高亮
                // 这是 Markwon 渲染管线中处理代码块的正确方式
                builder.syntaxHighlight(LuaSyntaxHighlight())
            }

            override fun afterSetText(textView: android.widget.TextView) {
                // 对已渲染的代码块区域补充 heading 加粗样式
                val spannable = textView.text as? Spannable ?: return
                applyHeadingBold(spannable)
            }
        })
        .build()

    init {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        setLineSpacing(0f, 1.3f)
        setTextColor(colorOnSurface)
        movementMethod = LinkMovementMethod.getInstance()
        setTextIsSelectable(true)
    }

    fun loadFromText(markdown: String?) {
        if (markdown.isNullOrEmpty()) {
            text = ""
            return
        }
        markwon.setMarkdown(this, markdown)
    }

    // ── Heading 加粗 ─────────────────────────────────────────

    private fun applyHeadingBold(spannable: Spannable) {
        val headingSpans = spannable.getSpans(
            0, spannable.length,
            io.noties.markwon.core.spans.HeadingSpan::class.java
        )
        for (span in headingSpans) {
            val start = spannable.getSpanStart(span)
            val end = spannable.getSpanEnd(span)
            spannable.setSpan(
                StyleSpan(Typeface.BOLD), start, end,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    // ── Lua 语法高亮（通过 SyntaxHighlight 接口） ─────────────

    /**
     * 实现 Markwon 的 SyntaxHighlight 接口。
     * Markwon 在渲染 FencedCodeBlock / IndentedCodeBlock 时会调用
     * highlight(info, code)，返回的 CharSequence 会被直接用于最终 Spanned。
     */
    private inner class LuaSyntaxHighlight : SyntaxHighlight {
        override fun highlight(info: String?, code: String): CharSequence {
            val lang = info?.trim()?.lowercase() ?: ""
            // 对 lua 代码块或未指定语言的代码块应用高亮
            return if (lang.isEmpty() || lang == "lua" || lang == "luaj" || lang == "luaj++") {
                buildHighlightedCode(code)
            } else {
                code
            }
        }
    }

    /**
     * 将 Lua 代码转为带 ForegroundColorSpan 的 SpannableStringBuilder。
     */
    private fun buildHighlightedCode(code: String): SpannableStringBuilder {
        val builder = SpannableStringBuilder(code)
        var i = 0
        while (i < code.length) {
            val c = code[i]
            when {
                // 行注释 --
                c == '-' && i + 1 < code.length && code[i + 1] == '-' -> {
                    val isBlock = i + 3 < code.length && code[i + 2] == '[' && code[i + 3] == '['
                    val endIdx = if (isBlock) {
                        val closeIdx = code.indexOf("]]", i + 4)
                        if (closeIdx >= 0) closeIdx + 2 else code.length
                    } else {
                        val nlIdx = code.indexOf('\n', i)
                        if (nlIdx >= 0) nlIdx else code.length
                    }
                    setHighlight(builder, i, endIdx, colorComment, italic = true)
                    i = endIdx
                }
                // 字符串 "..." 或 '...'
                c == '"' || c == '\'' -> {
                    val endIdx = findStringEnd(code, i, c)
                    setHighlight(builder, i, endIdx, colorString)
                    i = endIdx
                }
                // 长字符串 [[...]]
                c == '[' && i + 1 < code.length && code[i + 1] == '[' -> {
                    val endIdx = code.indexOf("]]", i + 2).let { if (it >= 0) it + 2 else code.length }
                    setHighlight(builder, i, endIdx, colorString)
                    i = endIdx
                }
                // 数字
                c.isDigit() || (c == '.' && i + 1 < code.length && code[i + 1].isDigit()) -> {
                    val endIdx = findNumberEnd(code, i)
                    setHighlight(builder, i, endIdx, colorNumber)
                    i = endIdx
                }
                // 标识符（关键字/内置函数）
                c.isLetter() || c == '_' -> {
                    val endIdx = findIdentEnd(code, i)
                    val word = code.substring(i, endIdx)
                    when (word) {
                        in KEYWORDS -> setHighlight(builder, i, endIdx, colorKeyword, bold = true)
                        in BUILTINS -> setHighlight(builder, i, endIdx, colorBuiltin)
                    }
                    i = endIdx
                }
                else -> i++
            }
        }
        return builder
    }

    private fun setHighlight(
        builder: SpannableStringBuilder, start: Int, end: Int,
        color: Int, bold: Boolean = false, italic: Boolean = false
    ) {
        if (start >= end || start < 0 || end > builder.length) return
        builder.setSpan(ForegroundColorSpan(color), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (bold) builder.setSpan(StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (italic) builder.setSpan(StyleSpan(Typeface.ITALIC), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    // ── 词法分析辅助 ─────────────────────────────────────────

    private fun findStringEnd(code: String, start: Int, quote: Char): Int {
        var i = start + 1
        while (i < code.length) {
            if (code[i] == '\\') { i += 2; continue }
            if (code[i] == quote) return i + 1
            i++
        }
        return code.length
    }

    private fun findNumberEnd(code: String, start: Int): Int {
        var i = start
        var hasDot = false
        if (i < code.length && code[i] == '0' && i + 1 < code.length && (code[i + 1] == 'x' || code[i + 1] == 'X')) {
            i += 2
            while (i < code.length && code[i].isLetterOrDigit()) i++
            return i
        }
        while (i < code.length) {
            when {
                code[i].isDigit() -> i++
                code[i] == '.' && !hasDot -> { hasDot = true; i++ }
                code[i] == 'e' || code[i] == 'E' -> {
                    i++
                    if (i < code.length && (code[i] == '+' || code[i] == '-')) i++
                }
                else -> break
            }
        }
        return i
    }

    private fun findIdentEnd(code: String, start: Int): Int {
        var i = start
        while (i < code.length && (code[i].isLetterOrDigit() || code[i] == '_')) i++
        return i
    }

    // ── 工具方法 ──────────────────────────────────────────────

    private fun dpToPx(dp: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, resources.displayMetrics)

    private fun spToPx(sp: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)

    companion object {
        // Lua 关键字
        private val KEYWORDS = setOf(
            "and", "break", "do", "else", "elseif", "end", "false", "for",
            "function", "goto", "if", "in", "local", "nil", "not", "or",
            "repeat", "return", "then", "true", "until", "while",
            // LuaJ++ 扩展
            "continue", "switch", "case", "default", "try", "catch",
            "lambda", "import", "require"
        )

        // Lua 内置函数
        private val BUILTINS = setOf(
            "print", "printf", "type", "tostring", "tonumber", "pairs", "ipairs",
            "pcall", "xpcall", "error", "assert", "select", "unpack",
            "setmetatable", "getmetatable", "rawget", "rawset",
            // NeLuaJ+ 全局
            "loadlayout", "task", "xTask", "thread", "timer", "call", "lazy"
        )
    }
}

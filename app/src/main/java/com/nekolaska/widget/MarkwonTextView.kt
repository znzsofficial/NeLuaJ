package com.nekolaska.widget

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineBackgroundSpan
import android.text.style.ReplacementSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.util.AttributeSet
import android.util.TypedValue
import com.google.android.material.color.MaterialColors
import com.google.android.material.textview.MaterialTextView
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.MarkwonConfiguration
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.core.spans.CodeBlockSpan
import io.noties.markwon.core.spans.CodeSpan
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import io.noties.markwon.ext.tables.TablePlugin
import io.noties.markwon.ext.tables.TableRowSpan
import io.noties.markwon.ext.tables.TableTheme
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

    private val tableTheme = TableTheme.buildWithDefaults(context)
        .tableBorderColor(colorOutlineVariant)
        .tableBorderWidth(dpToPx(1f).toInt())
        .tableCellPadding(dpToPx(6f).toInt())
        .tableHeaderRowBackgroundColor(colorSurfaceContainerHighest)
        .tableEvenRowBackgroundColor(0)
        .tableOddRowBackgroundColor(0)
        .build()

    private val markwon: Markwon = Markwon.builder(context)
        .usePlugin(HtmlPlugin.create())
        .usePlugin(LinkifyPlugin.create())
        .usePlugin(TablePlugin.create(tableTheme))
        .usePlugin(object : AbstractMarkwonPlugin() {
            override fun configureTheme(builder: MarkwonTheme.Builder) {
                builder
                    .codeTextColor(0) // 设置为 0，防止默认颜色干扰
                    .codeBackgroundColor(0) // 设置为 0，消除原生方块背景
                    .codeBlockTextColor(colorOnSurface)
                    .codeBlockBackgroundColor(0) // 设置为 0，我们将使用自定义圆角背景
                    .codeTypeface(Typeface.MONOSPACE)
                    .codeBlockTypeface(Typeface.MONOSPACE)
                    .codeTextSize(spToPx(13f).toInt())
                    .codeBlockMargin(dpToPx(12f).toInt()) 
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
                builder.syntaxHighlight(LuaSyntaxHighlight())
            }

            override fun beforeSetText(textView: android.widget.TextView, markdown: Spanned) {
                // 已在 loadFromText 中统一处理
            }
        })
        .usePlugin(StrikethroughPlugin.create())
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
        val spanned = markwon.toMarkdown(preprocessMarkdown(markdown))
        
        if (spanned is Spannable) {
            applyHeadingBold(spanned) 
            
            // 1. 处理行内代码 (CodeSpan) 为自定义圆角
            val codeSpans = spanned.getSpans(0, spanned.length, CodeSpan::class.java)
            for (span in codeSpans) {
                val start = spanned.getSpanStart(span)
                val end = spanned.getSpanEnd(span)

                if (isInsideTable(spanned, start, end)) {
                    spanned.removeSpan(span)
                    continue
                }

                val customSpan = RoundRectCodeSpan(
                    backgroundColor = colorSurfaceContainerHighest,
                    textColor = colorPrimary,
                    cornerRadius = dpToPx(4f),
                    padding = dpToPx(4f),
                    typeface = Typeface.MONOSPACE,
                    textSize = spToPx(13f)
                )
                spanned.removeSpan(span)
                spanned.setSpan(customSpan, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }

            // 2. 处理代码块 (CodeBlockSpan) 为圆角背景
            val codeBlockSpans = spanned.getSpans(0, spanned.length, CodeBlockSpan::class.java)
            for (span in codeBlockSpans) {
                val start = spanned.getSpanStart(span)
                val end = spanned.getSpanEnd(span)

                spanned.removeSpan(span)
                val roundRectBg = RoundRectCodeBlockSpan(
                    backgroundColor = colorSurfaceContainerHighest,
                    cornerRadius = dpToPx(12f),
                    padding = dpToPx(12f).toInt()
                )

                spanned.setSpan(roundRectBg, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                spanned.setSpan(TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                spanned.setSpan(
                    AbsoluteSizeSpan(spToPx(13f).toInt()),
                    start,
                    end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
        
        text = spanned
    }

    private fun preprocessMarkdown(markdown: String): String {
        return flattenMarkdownTables(markdown)
    }

    private fun flattenMarkdownTables(markdown: String): String {
        val lines = markdown.lines()
        val output = mutableListOf<String>()
        var i = 0
        var inFence = false

        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trim()

            if (trimmed.startsWith("```")) {
                inFence = !inFence
                output += line
                i++
                continue
            }

            if (!inFence && isTableHeader(lines, i)) {
                val tableLines = mutableListOf<String>()
                while (i < lines.size && isTableLikeLine(lines[i])) {
                    tableLines += lines[i]
                    i++
                }
                output += renderTableAsPlainText(tableLines)
                continue
            }

            output += line
            i++
        }

        return output.joinToString("\n")
    }

    private fun isTableHeader(lines: List<String>, index: Int): Boolean {
        if (index + 1 >= lines.size) return false
        return isTableLikeLine(lines[index]) && isTableSeparatorLine(lines[index + 1])
    }

    private fun isTableLikeLine(line: String): Boolean {
        val trimmed = line.trim()
        return trimmed.startsWith("|") && trimmed.endsWith("|") && trimmed.count { it == '|' } >= 2
    }

    private fun isTableSeparatorLine(line: String): Boolean {
        val trimmed = line.trim()
        if (!isTableLikeLine(trimmed)) return false
        return trimmed.removePrefix("|").removeSuffix("|").split("|").all { cell ->
            val value = cell.trim()
            value.isNotEmpty() && value.all { it == '-' || it == ':' || it == ' ' }
        }
    }

    private fun renderTableAsPlainText(tableLines: List<String>): List<String> {
        if (tableLines.size < 2) return tableLines

        val rows = tableLines.map { parseTableRow(it) }
        val headers = rows.firstOrNull().orEmpty()
        val dataRows = rows.drop(2)
        if (headers.isEmpty() || dataRows.isEmpty()) return tableLines

        val result = mutableListOf<String>()
        dataRows.forEachIndexed { rowIndex, row ->
            if (rowIndex > 0) result += ""
            if (headers.size == 2 && row.size >= 2) {
                result += "- ${headers[0]}：${row.getOrElse(0) { "" }}"
                result += "  ${headers[1]}：${row.getOrElse(1) { "" }}"
            } else {
                val pairs = headers.mapIndexed { idx, header ->
                    val value = row.getOrElse(idx) { "" }
                    if (header.isBlank()) value else "$header: $value"
                }
                result += "- " + pairs.joinToString("  |  ")
            }
        }
        return result
    }

    private fun parseTableRow(line: String): List<String> {
        return line.trim()
            .removePrefix("|")
            .removeSuffix("|")
            .split("|")
            .map { it.trim() }
    }

    private fun isInsideTable(spannable: Spannable, start: Int, end: Int): Boolean {
        val tableRows = spannable.getSpans(start, end, TableRowSpan::class.java)
        if (tableRows.isEmpty()) return false
        return tableRows.any { rowSpan ->
            val rowStart = spannable.getSpanStart(rowSpan)
            val rowEnd = spannable.getSpanEnd(rowSpan)
            start >= rowStart && end <= rowEnd
        }
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

    // ── 圆角背景行内代码 Span ──────────────────────────────────

    private class RoundRectCodeSpan(
        private val backgroundColor: Int,
        private val textColor: Int,
        private val cornerRadius: Float,
        private val padding: Float,
        private val typeface: Typeface,
        private val textSize: Float
    ) : ReplacementSpan() {

        override fun getSize(
            paint: Paint, text: CharSequence, start: Int, end: Int, fm: Paint.FontMetricsInt?
        ): Int {
            paint.typeface = typeface
            paint.textSize = textSize
            val width = paint.measureText(text, start, end)
            
            // 如果需要调整行高，可以在这里操作 fm
            if (fm != null) {
                val paintFm = paint.fontMetricsInt
                fm.ascent = paintFm.ascent - padding.toInt()
                fm.descent = paintFm.descent + padding.toInt()
                fm.top = paintFm.top - padding.toInt()
                fm.bottom = paintFm.bottom + padding.toInt()
            }
            
            return (width + padding * 3).toInt() // 稍微增加总宽度，避免圆角切到文字
        }

        override fun draw(
            canvas: Canvas, text: CharSequence, start: Int, end: Int, x: Float,
            top: Int, y: Int, bottom: Int, paint: Paint
        ) {
            paint.typeface = typeface
            paint.textSize = textSize
            val width = paint.measureText(text, start, end)
            
            // 计算背景范围，稍微缩小一点上下边界防止与其他行太挤
            val rect = RectF(
                x + padding / 2,
                top.toFloat() + padding / 2,
                x + width + padding * 1.5f,
                bottom.toFloat() - padding / 2
            )
            
            // 绘制背景
            paint.color = backgroundColor
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)
            
            // 绘制文字
            paint.color = textColor
            canvas.drawText(text, start, end, x + padding, y.toFloat(), paint)
        }
    }

    // ── 圆角背景大代码块 Span ──────────────────────────────────

    private class RoundRectCodeBlockSpan(
        private val backgroundColor: Int,
        private val cornerRadius: Float,
        private val padding: Int
    ) : LineBackgroundSpan, LeadingMarginSpan {

        override fun drawBackground(
            canvas: Canvas, paint: Paint,
            left: Int, right: Int, top: Int, baseline: Int, bottom: Int,
            text: CharSequence, start: Int, end: Int, lnum: Int
        ) {
            val spanned = text as? Spanned ?: return
            val spanStart = spanned.getSpanStart(this)
            val spanEnd = spanned.getSpanEnd(this)

            val oldColor = paint.color
            val oldStyle = paint.style

            paint.color = backgroundColor
            paint.style = Paint.Style.FILL

            val rect = RectF(
                left.toFloat() + padding / 2f,
                top.toFloat(),
                right.toFloat() - padding / 2f,
                bottom.toFloat()
            )

            val isFirstLine = start <= spanStart
            val isLastLine = end >= spanEnd

            when {
                isFirstLine && isLastLine -> {
                    canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)
                }

                isFirstLine -> {
                    drawPartialRoundRect(canvas, rect, paint, topRounded = true, bottomRounded = false)
                }

                isLastLine -> {
                    drawPartialRoundRect(canvas, rect, paint, topRounded = false, bottomRounded = true)
                }

                else -> {
                    canvas.drawRect(rect, paint)
                }
            }

            paint.color = oldColor
            paint.style = oldStyle
        }

        private fun drawPartialRoundRect(
            canvas: Canvas,
            rect: RectF,
            paint: Paint,
            topRounded: Boolean,
            bottomRounded: Boolean
        ) {
            val radii = floatArrayOf(
                if (topRounded) cornerRadius else 0f,
                if (topRounded) cornerRadius else 0f,
                if (topRounded) cornerRadius else 0f,
                if (topRounded) cornerRadius else 0f,
                if (bottomRounded) cornerRadius else 0f,
                if (bottomRounded) cornerRadius else 0f,
                if (bottomRounded) cornerRadius else 0f,
                if (bottomRounded) cornerRadius else 0f
            )
            val path = Path().apply {
                addRoundRect(rect, radii, Path.Direction.CW)
            }
            canvas.drawPath(path, paint)
        }

        override fun getLeadingMargin(first: Boolean): Int = padding
        override fun drawLeadingMargin(
            c: Canvas?, p: Paint?, x: Int, dir: Int, top: Int,
            baseline: Int, bottom: Int, text: CharSequence?, start: Int, 
            end: Int, first: Boolean, layout: Layout?
        ) {}
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

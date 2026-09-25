package com.nekolaska.ai

import android.text.Editable
import android.text.Html
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import org.xml.sax.XMLReader

/**
 * Markdown 渲染的 Html.TagHandler：处理 HtmlCompat.fromHtml 不识别的标签。
 *
 * - <hr>：着色的水平分割线（Unicode ─），无 Closing 内容
 * - <table>：整块加背景色 + 左缩进（配 <tr> 换行 / <td> 间隔组成表格视觉）
 * - <blockquote>：已由 HtmlCompat 原生 QuoteSpan 处理（左侧竖线），不在此重复
 */
class MarkdownTagHandler(
    private val tableBgColor: Int,
    private val hrColor: Int
) : Html.TagHandler {

    private class TableMark

    override fun handleTag(
        opening: Boolean,
        tag: String,
        output: Editable,
        xmlReader: XMLReader
    ) {
        when (tag.lowercase()) {
            "hr" -> if (opening) {
                val pos = output.length
                output.append("\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n")
                output.setSpan(
                    ForegroundColorSpan(hrColor),
                    pos, output.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            "table" -> if (opening) {
                output.setSpan(
                    TableMark(),
                    output.length, output.length,
                    Spanned.SPAN_MARK_MARK
                )
                output.append("\n")
            } else {
                val spans = output.getSpans(0, output.length, TableMark::class.java)
                val mark = spans.lastOrNull() ?: return
                val start = output.getSpanStart(mark)
                output.removeSpan(mark)
                if (start >= 0 && start < output.length) {
                    output.setSpan(
                        BackgroundColorSpan(tableBgColor),
                        start, output.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    output.setSpan(
                        LeadingMarginSpan.Standard(24),
                        start, output.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }

            // 每行一个换行
            "tr" -> if (opening) output.append("\n")

            // 单元格之间双空格分隔
            "td", "th" -> if (!opening) output.append("  ")
        }
    }
}

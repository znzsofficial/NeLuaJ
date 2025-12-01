package com.androlua

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.TextView
import github.znzsofficial.neluaj.R
import androidx.core.graphics.toColorInt

class LogAdapter(context: Context) : ArrayAdapter<String>(context, R.layout.log_list_item) {
    companion object {
        private val COLOR_LUA_ERROR = "#FFC107".toColorInt()
        private val COLOR_VM_ERROR = "#F44336".toColorInt()
        private val COLOR_JAVA_ERROR = "#FF9800".toColorInt()
        private val COLOR_SYNTAX_ERROR = "#9C27B0".toColorInt()
        private val COLOR_DEFAULT_ERROR = "#EF5350".toColorInt()
        private val COLOR_LOG = "#C0C0C0".toColorInt()
        private const val COLOR_TRANSPARENT = Color.TRANSPARENT
    }

    private val inflater: LayoutInflater = LayoutInflater.from(context)

    // data class 是 ViewHolder 的完美选择，简洁且自动生成 equals/hashCode 等
    private data class ViewHolder(
        val logMessage: TextView,
        val logTag: TextView,
        val border: GradientDrawable
    )

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view: View
        val holder: ViewHolder

        if (convertView == null) {
            view = inflater.inflate(R.layout.log_list_item, parent, false)
            val logMessageView = view.findViewById<TextView>(R.id.log_message)
            val background = logMessageView.background.mutate() as LayerDrawable
            holder = ViewHolder(
                logMessage = logMessageView,
                logTag = view.findViewById(R.id.log_tag),
                border = background.findDrawableByLayerId(R.id.log_frame_border) as GradientDrawable
            )
            view.tag = holder
        } else {
            view = convertView
            holder = view.tag as ViewHolder
        }

        val logMessage = getItem(position)
        holder.logMessage.text = logMessage

        // 调用优化后的逻辑函数
        setTagAndBorder(holder, logMessage)

        return view
    }

    /**
     * 根据日志内容设置标签和边框，使用 when 表达式进行优化
     */
    private fun setTagAndBorder(holder: ViewHolder, logMessage: String?) {
        if (logMessage == null) {
            // 安全处理 null 消息
            holder.logTag.visibility = View.GONE
            holder.border.setColor(COLOR_TRANSPARENT)
            return
        }

        // when 表达式根据条件返回一个 Pair(标签文本, 颜色)，代码更整洁
        val (tagText, color) = when {
            "vm error:" in logMessage ->
                "VM ERROR" to COLOR_VM_ERROR

            "syntax error" in logMessage ->
                "SYNTAX ERROR" to COLOR_SYNTAX_ERROR

            "no coercible public method" in logMessage || "coercion error" in logMessage || "method cannot be called without instance" in logMessage ->
                "JAVA ERROR" to COLOR_JAVA_ERROR

            logMessage.startsWith("xTask") ->
                "TASK ERROR" to COLOR_JAVA_ERROR

            "global '" in logMessage || "local '" in logMessage || "attempt to call a nil value" in logMessage || "attempt to call nil" in logMessage ->
                "LUA RUNTIME ERROR" to COLOR_LUA_ERROR

            logMessage.startsWith("Error:") || "stack traceback" in logMessage || "bad argument" in logMessage ->
                "ERROR" to COLOR_DEFAULT_ERROR

            else ->
                "LOG" to COLOR_LOG
        }

        // 在逻辑判断结束后，统一更新一次 UI
        updateViews(holder, tagText, color)
    }

    /**
     * 统一的 UI 更新函数
     */
    private fun updateViews(holder: ViewHolder, tagText: String, color: Int) {
        holder.logTag.visibility = View.VISIBLE
        holder.logTag.text = tagText
        holder.border.setColor(color)
    }
}
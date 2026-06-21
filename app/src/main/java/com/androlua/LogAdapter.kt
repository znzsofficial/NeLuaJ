package com.androlua

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.toColorInt
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import github.znzsofficial.neluaj.R

/**
 * 日志列表适配器
 * 支持不同日志级别的颜色分类显示
 */
class LogAdapter : RecyclerView.Adapter<LogAdapter.LogViewHolder>() {

    private val items = mutableListOf<String>()

    /**
     * 日志级别枚举
     * @param label 显示标签
     * @param colorInt 颜色值（Int）
     */
    private enum class LogLevel(val label: String, val colorInt: Int) {
        VM_ERROR("VM ERROR", "#D32F2F".toColorInt()),
        SYNTAX_ERROR("SYNTAX", "#7B1FA2".toColorInt()),
        JAVA_ERROR("JAVA", "#E65100".toColorInt()),
        TASK_ERROR("TASK", "#E65100".toColorInt()),
        LUA_RUNTIME("LUA", "#F9A825".toColorInt()),
        DEFAULT_ERROR("ERROR", "#C62828".toColorInt()),
        LOG("LOG", "#78909C".toColorInt());
    }

    /**
     * ViewHolder
     */
    class LogViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val card: MaterialCardView = itemView as MaterialCardView
        val indicator: View = itemView.findViewById(R.id.log_indicator)
        val logTag: TextView = itemView.findViewById(R.id.log_tag)
        val logMessage: TextView = itemView.findViewById(R.id.log_message)
        val tagBackground: GradientDrawable = logTag.background.mutate() as GradientDrawable
    }

    // ── Adapter 核心方法 ─────────────────────────────────────────

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LogViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.log_list_item, parent, false)
        return LogViewHolder(view)
    }

    override fun onBindViewHolder(holder: LogViewHolder, position: Int) {
        val message = items[position]
        holder.logMessage.text = message

        val level = classifyLog(message)
        val color = level.colorInt

        // 设置标签
        holder.logTag.text = level.label
        holder.tagBackground.setColor(color)
        holder.logTag.setTextColor(
            if (ColorUtils.calculateLuminance(color) > 0.45) Color.BLACK else Color.WHITE
        )

        // 设置左侧色条
        holder.indicator.setBackgroundColor(color)

        // 错误级别：卡片描边使用级别色的淡化版；LOG 级别保持默认描边
        holder.card.strokeColor = if (level != LogLevel.LOG) {
            ColorUtils.blendARGB(color, Color.TRANSPARENT, 0.5f)
        } else {
            com.google.android.material.color.MaterialColors.getColor(
                holder.card, com.google.android.material.R.attr.colorOutlineVariant
            )
        }
    }

    override fun getItemCount(): Int = items.size

    // ── 数据操作 ─────────────────────────────────────────────────

    /**
     * 添加日志消息
     */
    fun add(message: String) {
        items.add(message)
        notifyItemInserted(items.size - 1)
    }

    /**
     * 清空所有日志
     */
    fun clear() {
        val size = items.size
        items.clear()
        notifyItemRangeRemoved(0, size)
    }

    /**
     * 获取指定位置的日志消息
     */
    fun getItem(position: Int): String = items[position]

    /**
     * 日志数量
     */
    val count: Int get() = items.size

    // ── 日志分类 ─────────────────────────────────────────────────

    /**
     * 根据消息内容分类日志级别
     * 匹配改进后的错误信息格式
     */
    private fun classifyLog(message: String): LogLevel = when {
        // Lua VM 错误
        "vm error:" in message ->
            LogLevel.VM_ERROR

        // 语法错误
        "syntax error" in message ->
            LogLevel.SYNTAX_ERROR

        // Java 相关错误（匹配改进后的错误信息）
        "no matching overload found" in message
                || "argument count mismatch" in message
                || "exception in Java method" in message
                || "failed to invoke Java method" in message
                || "no matching constructor" in message
                || "failed to create instance" in message
                || "expected a Java interface" in message
                || "not an interface" in message ->
            LogLevel.JAVA_ERROR

        // xTask 错误
        message.startsWith("xTask") ->
            LogLevel.TASK_ERROR

        // Lua 运行时错误
        "global '" in message
                || "local '" in message
                || "attempt to call a nil value" in message
                || "attempt to call nil" in message ->
            LogLevel.LUA_RUNTIME

        // 通用错误
        message.startsWith("Error:")
                || "stack traceback" in message
                || "bad argument" in message ->
            LogLevel.DEFAULT_ERROR

        // 普通日志
        else ->
            LogLevel.LOG
    }
}

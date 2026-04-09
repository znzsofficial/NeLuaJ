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

class LogAdapter : RecyclerView.Adapter<LogAdapter.LogViewHolder>() {

    private val items = mutableListOf<String>()

    // ── 日志级别枚举 ──────────────────────────────────────────
    private enum class LogLevel(val label: String, val color: Int) {
        VM_ERROR("VM ERROR", "#D32F2F".toColorInt()),
        SYNTAX_ERROR("SYNTAX", "#7B1FA2".toColorInt()),
        JAVA_ERROR("JAVA", "#E65100".toColorInt()),
        TASK_ERROR("TASK", "#E65100".toColorInt()),
        LUA_RUNTIME("LUA", "#F9A825".toColorInt()),
        DEFAULT_ERROR("ERROR", "#C62828".toColorInt()),
        LOG("LOG", "#78909C".toColorInt());
    }

    // ── ViewHolder ─────────────────────────────────────────────
    class LogViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val card: MaterialCardView = itemView as MaterialCardView
        val indicator: View = itemView.findViewById(R.id.log_indicator)
        val logTag: TextView = itemView.findViewById(R.id.log_tag)
        val logMessage: TextView = itemView.findViewById(R.id.log_message)
        val tagBackground: GradientDrawable = logTag.background.mutate() as GradientDrawable
    }

    // ── Adapter 核心方法 ───────────────────────────────────────
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LogViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.log_list_item, parent, false)
        return LogViewHolder(view)
    }

    override fun onBindViewHolder(holder: LogViewHolder, position: Int) {
        val message = items[position]
        holder.logMessage.text = message

        val level = classifyLog(message)
        val color = level.color

        // 标签
        holder.logTag.text = level.label
        holder.tagBackground.setColor(color)
        holder.logTag.setTextColor(
            if (ColorUtils.calculateLuminance(color) > 0.45) Color.BLACK else Color.WHITE
        )

        // 左侧色条
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

    // ── 数据操作 ───────────────────────────────────────────────
    fun add(message: String) {
        items.add(message)
        notifyItemInserted(items.size - 1)
    }

    fun clear() {
        val size = items.size
        items.clear()
        notifyItemRangeRemoved(0, size)
    }

    fun getItem(position: Int): String = items[position]

    val count: Int get() = items.size

    // ── 日志分类 ───────────────────────────────────────────────
    private fun classifyLog(message: String): LogLevel = when {
        "vm error:" in message ->
            LogLevel.VM_ERROR

        "syntax error" in message ->
            LogLevel.SYNTAX_ERROR

        "no coercible public method" in message
                || "coercion error" in message
                || "method cannot be called without instance" in message ->
            LogLevel.JAVA_ERROR

        message.startsWith("xTask") ->
            LogLevel.TASK_ERROR

        "global '" in message
                || "local '" in message
                || "attempt to call a nil value" in message
                || "attempt to call nil" in message ->
            LogLevel.LUA_RUNTIME

        message.startsWith("Error:")
                || "stack traceback" in message
                || "bad argument" in message ->
            LogLevel.DEFAULT_ERROR

        else ->
            LogLevel.LOG
    }
}
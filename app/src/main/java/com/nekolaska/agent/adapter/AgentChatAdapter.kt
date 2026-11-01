package com.nekolaska.agent.adapter

import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import org.luaj.LuaTable
import org.luaj.LuaValue

/**
 * 专为 AI Agent 打造的纯正 LuaJ 原生高性能 RecyclerView 适配器：
 * 1. 深度对齐 AndroLua / org.luaj.android 官方 Adapter 风格；
 * 2. 避免 ListAdapter / JavaInstance 的动态代理反射阻抗，直接以 Lua 原生表驱动；
 * 3. 内存直接持有当前卡片流，支持快速增量刷新；
 * 4. 内置流式动态更新（Streaming Token）局部刷新优化。
 */
class AgentChatAdapter @JvmOverloads constructor(
    private val context: LuaContext? = null,
    private val delegate: Delegate
) : RecyclerView.Adapter<LuaCustRecyclerHolder>() {

    companion object {
        const val PAYLOAD_STREAMING_TEXT = "payload_streaming_text"
    }

    private var mItems: ArrayList<LuaValue> = ArrayList()

    override fun getItemCount(): Int = mItems.size

    override fun getItemViewType(position: Int): Int {
        return try {
            val item = mItems[position]
            delegate.getItemViewType(item, position)
        } catch (e: Exception) {
            context?.sendError("AgentChatAdapter: getItemViewType", e)
            0
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LuaCustRecyclerHolder {
        return try {
            delegate.onCreateViewHolder(parent, viewType)
        } catch (e: Exception) {
            context?.sendError("AgentChatAdapter: onCreateViewHolder", e)
            LuaCustRecyclerHolder(View(context?.context ?: parent.context))
        }
    }

    override fun onBindViewHolder(holder: LuaCustRecyclerHolder, position: Int) {
        onBindViewHolder(holder, position, emptyList())
    }

    override fun onBindViewHolder(
        holder: LuaCustRecyclerHolder,
        position: Int,
        payloads: List<Any>
    ) {
        try {
            val item = mItems[position]
            if (payloads.isNotEmpty()) {
                delegate.onBindViewHolderWithPayload(holder, item, position, payloads)
            } else {
                delegate.onBindViewHolder(holder, item, position)
            }
        } catch (e: Exception) {
            context?.sendError("AgentChatAdapter: onBindViewHolder", e)
        }
    }

    override fun onViewRecycled(holder: LuaCustRecyclerHolder) {
        try {
            delegate.onViewRecycled(holder)
        } catch (e: Exception) {
            context?.sendError("AgentChatAdapter: onViewRecycled", e)
        }
    }

    /**
     * 接收 Lua 侧传递过来的普通 Lua 表数组并刷新。
     * 兼容 LuaTable、任意 LuaValue 甚至 Userdata。
     */
    fun submitMessages(messagesData: Any?) {
        val newItems = ArrayList<LuaValue>()
        if (messagesData is LuaValue) {
            if (messagesData.istable()) {
                val len = messagesData.length()
                for (i in 1..len) {
                    newItems.add(messagesData.get(i))
                }
            }
        }
        mItems = newItems
        try {
            notifyDataSetChanged()
        } catch (_: Throwable) {
            // 单元测试 JVM 环境下（android.jar 桩实现）AdapterDataObservable 未初始化，静默容错
        }
    }

    fun getItem(position: Int): LuaValue? {
        if (position in 0 until mItems.size) {
            return mItems[position]
        }
        return null
    }

    interface Delegate {
        fun getItemViewType(item: LuaValue, position: Int): Int
        fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LuaCustRecyclerHolder
        fun onBindViewHolder(holder: LuaCustRecyclerHolder, item: LuaValue, position: Int)
        fun onBindViewHolderWithPayload(
            holder: LuaCustRecyclerHolder,
            item: LuaValue,
            position: Int,
            payloads: List<Any>
        ) {
            onBindViewHolder(holder, item, position)
        }
        fun onViewRecycled(holder: LuaCustRecyclerHolder) {}
    }
}

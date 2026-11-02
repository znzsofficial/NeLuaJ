package com.nekolaska.agent.adapter

import android.view.View
import android.view.ViewGroup
import android.os.Handler
import android.os.Looper
import androidx.recyclerview.widget.DiffUtil
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

    private val cards = AgentCardList()
    private var recycler: RecyclerView? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val pendingUpdates = ArrayDeque<() -> Unit>()
    private var drainScheduled = false

    private fun dispatchUpdate(update: () -> Unit) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { dispatchUpdate(update) }
        } else if (drainScheduled || recycler?.isComputingLayout == true) {
            pendingUpdates.addLast(update)
            if (!drainScheduled) {
                drainScheduled = true
                mainHandler.post { drainUpdates() }
            }
        } else {
            update()
        }
    }

    private fun drainUpdates() {
        if (recycler?.isComputingLayout == true) {
            mainHandler.post { drainUpdates() }
            return
        }
        try {
            while (pendingUpdates.isNotEmpty()) pendingUpdates.removeFirst().invoke()
        } finally {
            drainScheduled = false
        }
    }

    override fun getItemCount(): Int = cards.size

    override fun getItemViewType(position: Int): Int {
        return try {
            val item = cards[position]
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
            val item = cards[position]
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

    override fun onAttachedToRecyclerView(recyclerView: RecyclerView) {
        super.onAttachedToRecyclerView(recyclerView)
        recycler = recyclerView
    }

    override fun onDetachedFromRecyclerView(recyclerView: RecyclerView) {
        recycler = null
        super.onDetachedFromRecyclerView(recyclerView)
    }

    /**
     * 接收 Lua 侧传递过来的普通 Lua 表数组并刷新。
     * 兼容 LuaTable、任意 LuaValue 甚至 Userdata。
     */
    fun submitMessages(messagesData: Any?) {
        dispatchUpdate {
            val newItems = ArrayList<LuaValue>()
            if (messagesData is LuaValue && messagesData.istable()) {
                val len = messagesData.length()
                for (i in 1..len) {
                    newItems.add(messagesData.get(i))
                }
            }
            cards.replace(newItems).dispatchUpdatesTo(this)
        }
    }

    fun getItem(position: Int): LuaValue? {
        if (position in 0 until cards.size) {
            return cards[position]
        }
        return null
    }

    fun updateStreamingText(streamId: Int, text: String): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { updateStreamingText(streamId, text) }
            return true
        }
        if (!cards.hasStream(streamId.toString())) return false
        dispatchUpdate {
            val position = cards.updateStream(streamId.toString(), text)
            if (position >= 0) notifyItemChanged(position, PAYLOAD_STREAMING_TEXT)
        }
        return true
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

/** Immutable comparison snapshots: Lua messages themselves remain mutable. */
internal class AgentCardList {
    private data class Card(
        val value: LuaValue,
        val key: String,
        val type: Int,
        val streamId: String,
        val message: LuaValue,
        val content: List<String>
    )

    private var items = emptyList<Card>()
    val size: Int get() = items.size
    operator fun get(position: Int): LuaValue = items[position].value
    fun hasStream(streamId: String): Boolean = items.any { it.type == 4 && it.streamId == streamId }

    fun updateStream(streamId: String, text: String): Int {
        val index = items.indexOfFirst { it.type == 4 && it.streamId == streamId }
        if (index < 0) return -1
        val value = LuaTable()
        val previous = items[index].value.checktable()
        previous.keys().forEach { value.set(it, previous.get(it)) }
        value.set("text", LuaValue.valueOf(text))
        items = items.toMutableList().also { it[index] = snapshot(value, index) }
        return index
    }

    private fun snapshot(value: LuaValue, index: Int): Card {
        val type = value.get("viewType").optint(0)
        val message = value.get("message")
        val subtask = value.get("subtask")
        val content = listOf(
            "content", "text", "error", "title", "body", "isLastUser", "isLastAssistant",
            "toolName", "result", "streamId", "messageIndex"
        ).map { value.get(it).tojstring() } + listOf(
            fingerprint(value.get("args")),
            if (message.istable()) message.get("reasoning_content").tojstring() else "",
            if (message.istable()) message.get("continuation_state").tojstring() else ""
        ) + listOf("task", "rounds", "tool", "done").map {
            if (subtask.istable()) subtask.get(it).tojstring() else ""
        }
        return Card(value, value.get("stableId").optjstring("index_$index"), type,
            value.get("streamId").tojstring(), message, content)
    }

    private fun fingerprint(value: LuaValue, depth: Int = 0): String {
        if (!value.istable() || depth >= 16) return value.typename() + ":" + value.tojstring()
        return value.checktable().keys().map { key ->
            val k = fingerprint(key, depth + 1)
            val v = fingerprint(value.get(key), depth + 1)
            "${k.length}:$k${v.length}:$v"
        }.sorted().joinToString("|")
    }

    fun replace(values: List<LuaValue>): DiffUtil.DiffResult {
        val old = items
        val next = values.mapIndexed { index, value -> snapshot(value, index) }
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize() = old.size
            override fun getNewListSize() = next.size
            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
                val a = old[oldItemPosition]
                val b = next[newItemPosition]
                return a.key == b.key && a.type == b.type
            }
            override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
                val a = old[oldItemPosition]
                val b = next[newItemPosition]
                return a.content == b.content && a.message === b.message
            }
            override fun getChangePayload(oldItemPosition: Int, newItemPosition: Int): Any? {
                val a = old[oldItemPosition]
                val b = next[newItemPosition]
                return if (a.type == 4 && b.type == 4 && a.streamId == b.streamId)
                    AgentChatAdapter.PAYLOAD_STREAMING_TEXT else null
            }
        })
        items = next
        return diff
    }
}

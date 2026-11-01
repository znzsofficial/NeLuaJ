package github.znzsofficial.adapter

import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import com.nekolaska.ktx.toLuaValue
import org.luaj.LuaTable
import org.luaj.LuaValue

/**
 * 修复版的通用 RecyclerListAdapter：
 * 1. 严格遵守 Android 官方 ListAdapter 契约：由内部 AsyncListDiffer 驱动 getItemCount()，
 *    彻底消除 Inconsistency detected 异常。若外部提供自定义列表，则平滑作为备选。
 * 2. 暴露 getItem(position) 与 submitList(LuaTable) 给 Lua 脚本使用。
 * 3. 避免 DiffCallback 频繁类型转换。
 */
open class RecyclerListAdapter @JvmOverloads constructor(
    open var mContext: LuaContext? = null,
    private val adapterCreator: Creator
) : ListAdapter<Any, LuaCustRecyclerHolder>(DiffCallback(adapterCreator)) {

    override fun onBindViewHolder(viewHolder: LuaCustRecyclerHolder, i: Int) {
        try {
            adapterCreator.onBindViewHolder(viewHolder, i)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerListAdapter: onBindViewHolder", e)
        }
    }

    override fun onBindViewHolder(
        holder: LuaCustRecyclerHolder,
        position: Int,
        payloads: MutableList<Any>
    ) {
        if (payloads.isEmpty()) {
            super.onBindViewHolder(holder, position, payloads)
        } else {
            try {
                adapterCreator.onBindViewHolder(holder, position, payloads)
            } catch (e: Exception) {
                mContext?.sendError("RecyclerListAdapter: onBindViewHolderPayload", e)
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LuaCustRecyclerHolder {
        val holder: LuaCustRecyclerHolder? = try {
            adapterCreator.onCreateViewHolder(parent, viewType)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerListAdapter: onCreateViewHolder", e)
            null
        }
        return holder ?: run {
            LuaCustRecyclerHolder(View(mContext?.context ?: parent.context))
        }
    }

    override fun onViewRecycled(viewHolder: LuaCustRecyclerHolder) {
        try {
            adapterCreator.onViewRecycled(viewHolder)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerListAdapter: onViewRecycled", e)
        }
    }

    private var isListSubmitted = false

    override fun submitList(list: MutableList<Any>?) {
        isListSubmitted = true
        super.submitList(list)
    }

    override fun submitList(list: MutableList<Any>?, commitCallback: Runnable?) {
        isListSubmitted = true
        super.submitList(list, commitCallback)
    }

    /** 严格遵守 ListAdapter 规范：若已通过 submitList 提交过列表，必须完全以 ListAdapter 数据源为准，防止 differ 撕裂崩溃 */
    override fun getItemCount(): Int {
        if (isListSubmitted) {
            return super.getItemCount()
        }
        return try {
            adapterCreator.getItemCount()
        } catch (e: Exception) {
            mContext?.sendError("RecyclerListAdapter: getItemCount", e)
            0
        }
    }

    override fun getItemViewType(i: Int): Int {
        return try {
            adapterCreator.getItemViewType(i)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerListAdapter: getItemViewType", e)
            -1
        }
    }

    public override fun getItem(position: Int): Any {
        return super.getItem(position)
    }

    /** 供 Lua 端直接提交 LuaTable 数据集 */
    fun submitLuaTable(table: LuaTable) {
        val list = ArrayList<Any>(table.length())
        for (i in 1..table.length()) {
            list.add(table[i])
        }
        super.submitList(list)
    }

    internal class DiffCallback(private val adapterCreator: Creator) :
        DiffUtil.ItemCallback<Any>() {
        override fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean {
            return adapterCreator.areItemsTheSame(
                if (oldItem is LuaValue) oldItem else oldItem.toLuaValue(),
                if (newItem is LuaValue) newItem else newItem.toLuaValue()
            )
        }

        override fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean {
            return adapterCreator.areContentsTheSame(
                if (oldItem is LuaValue) oldItem else oldItem.toLuaValue(),
                if (newItem is LuaValue) newItem else newItem.toLuaValue()
            )
        }
    }

    interface Creator {
        fun getItemCount(): Int
        fun getItemViewType(i: Int): Int
        fun onBindViewHolder(viewHolder: RecyclerView.ViewHolder?, i: Int)
        fun onBindViewHolder(viewHolder: RecyclerView.ViewHolder?, i: Int, payloads: List<Any>?) {}
        fun onCreateViewHolder(viewGroup: ViewGroup?, i: Int): LuaCustRecyclerHolder
        fun onViewRecycled(viewHolder: RecyclerView.ViewHolder?)
        fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean
        fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean
    }
}

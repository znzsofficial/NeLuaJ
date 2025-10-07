package github.znzsofficial.adapter

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import com.nekolaska.ktx.toLuaValue

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

    override fun getItemCount(): Int {
        return try {
            return adapterCreator.getItemCount()
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

    internal class DiffCallback(private val adapterCreator: Creator) :
        DiffUtil.ItemCallback<Any>() {
        override fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean {
            return adapterCreator.areItemsTheSame(
                oldItem.toLuaValue(),
                newItem.toLuaValue()
            )
        }

        override fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean {
            return adapterCreator.areContentsTheSame(
                oldItem.toLuaValue(),
                newItem.toLuaValue()
            )
        }
    }

    interface Creator {
        fun getItemCount(): Int
        fun getItemViewType(i: Int): Int
        fun onBindViewHolder(viewHolder: RecyclerView.ViewHolder?, i: Int)
        fun onCreateViewHolder(viewGroup: ViewGroup?, i: Int): LuaCustRecyclerHolder
        fun onViewRecycled(viewHolder: RecyclerView.ViewHolder?)
        fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean
        fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean
    }
}

package github.znzsofficial.adapter

import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import org.luaj.LuaValue

open class RecyclerListAdapter : ListAdapter<LuaValue?, LuaCustRecyclerHolder?> {
    open lateinit var adapterCreator: Creator
    var mContext: LuaContext?

    constructor(creator: Creator) : super(DiffCallback(creator)) {
        adapterCreator = creator
        mContext = null
    }

    constructor(context: LuaContext?, creator: Creator) : super(DiffCallback(creator)) {
        mContext = context
        adapterCreator = creator
    }

    override fun onBindViewHolder(viewHolder: LuaCustRecyclerHolder, i: Int) {
        try {
            adapterCreator.onBindViewHolder(viewHolder, i)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerListAdapter: onBindViewHolder", e)
        }
    }

    override fun onCreateViewHolder(viewGroup: ViewGroup, i: Int): LuaCustRecyclerHolder {
        return try {
            adapterCreator.onCreateViewHolder(viewGroup, i)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerListAdapter: onCreateViewHolder", e)
            LuaCustRecyclerHolder(null)
        }
    }

    override fun onViewRecycled(viewHolder: LuaCustRecyclerHolder) {
        try {
            adapterCreator.onViewRecycled(viewHolder)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerListAdapter: onViewRecycled", e)
        }
    }

    override fun getItemCount(): Int {
        return try {
            adapterCreator.itemCount.toInt()
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerListAdapter: getItemCount", e)
            0
        }
    }

    override fun getItemViewType(i: Int): Int {
        return try {
            adapterCreator.getItemViewType(i).toInt()
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerListAdapter: getItemViewType", e)
            -1
        }
    }

    internal class DiffCallback(private val adapterCreator: Creator) :
        DiffUtil.ItemCallback<LuaValue?>() {
        override fun areItemsTheSame(oldItem: LuaValue, newItem: LuaValue): Boolean {
            return adapterCreator.areItemsTheSame(oldItem, newItem)
        }

        override fun areContentsTheSame(oldItem: LuaValue, newItem: LuaValue): Boolean {
            return adapterCreator.areContentsTheSame(oldItem, newItem)
        }
    }

    interface Creator {
        val itemCount: Long
        fun getItemViewType(i: Int): Long
        fun onBindViewHolder(viewHolder: RecyclerView.ViewHolder?, i: Int)
        fun onCreateViewHolder(viewGroup: ViewGroup?, i: Int): LuaCustRecyclerHolder
        fun onViewRecycled(viewHolder: RecyclerView.ViewHolder?)
        fun areItemsTheSame(oldItem: Any, newItem: Any): Boolean
        fun areContentsTheSame(oldItem: Any, newItem: Any): Boolean
        abstract fun getPopupText(view: View, position: Int): CharSequence?
    }
}

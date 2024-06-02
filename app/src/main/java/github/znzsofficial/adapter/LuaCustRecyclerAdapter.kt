package github.znzsofficial.adapter

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext
import github.znzsofficial.adapter.RecyclerListAdapter.Creator

open class LuaCustRecyclerAdapter @JvmOverloads constructor(
    open var mContext: LuaContext? = null,
    private val adapterCreator: Creator
) : RecyclerView.Adapter<LuaCustRecyclerHolder>() {

    override fun getItemCount(): Int {
        return try {
            adapterCreator.itemCount.toInt()
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerAdapter: getItemCount", e)
            0
        }
    }

    override fun getItemViewType(i: Int): Int {
        return try {
            adapterCreator.getItemViewType(i).toInt()
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerAdapter: getItemViewType", e)
            -1
        }
    }

    override fun onBindViewHolder(holder: LuaCustRecyclerHolder, i: Int) {
        try {
            adapterCreator.onBindViewHolder(holder, i)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerAdapter: onBindViewHolder", e)
        }
    }

    override fun onCreateViewHolder(viewGroup: ViewGroup, i: Int): LuaCustRecyclerHolder {
        return try {
            adapterCreator.onCreateViewHolder(viewGroup, i)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerAdapter: onCreateViewHolder", e)
            LuaCustRecyclerHolder(View(mContext as Context))
        }
    }


    override fun onViewRecycled(holder: LuaCustRecyclerHolder) {
        try {
            adapterCreator.onViewRecycled(holder)
        } catch (e: Exception) {
            e.printStackTrace()
            mContext?.sendError("RecyclerAdapter: onViewRecycled", e)
        }
    }

    interface Creator {
        val itemCount: Long
        fun getItemViewType(i: Int): Long
        fun onBindViewHolder(viewHolder: LuaCustRecyclerHolder, i: Int)
        fun onCreateViewHolder(viewGroup: ViewGroup?, i: Int): LuaCustRecyclerHolder
        fun onViewRecycled(viewHolder: LuaCustRecyclerHolder)
    }
}

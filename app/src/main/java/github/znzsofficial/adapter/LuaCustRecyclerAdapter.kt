package github.znzsofficial.adapter

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext

open class LuaCustRecyclerAdapter @JvmOverloads constructor(
    open var mContext: LuaContext? = null,
    private val adapterCreator: Creator
) : RecyclerView.Adapter<LuaCustRecyclerHolder>() {

    override fun getItemCount(): Int {
        return try {
            adapterCreator.getItemCount()
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: getItemCount", e)
            0
        }
    }

    override fun getItemViewType(i: Int): Int {
        return try {
            adapterCreator.getItemViewType(i)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: getItemViewType", e)
            -1
        }
    }

    override fun onBindViewHolder(holder: LuaCustRecyclerHolder, position: Int) {
        try {
            adapterCreator.onBindViewHolder(holder, position, null)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: onBindViewHolder", e)
        }
    }

    override fun onBindViewHolder(
        holder: LuaCustRecyclerHolder,
        position: Int,
        payloads: List<Any>
    ) {
        try {
            adapterCreator.onBindViewHolder(holder, position, payloads)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: onBindViewHolder", e)
        }
    }

    override fun onCreateViewHolder(viewGroup: ViewGroup, i: Int): LuaCustRecyclerHolder {
        return try {
            adapterCreator.onCreateViewHolder(viewGroup, i)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: onCreateViewHolder", e)
            LuaCustRecyclerHolder(View(mContext as Context))
        }
    }


    override fun onViewRecycled(holder: LuaCustRecyclerHolder) {
        try {
            adapterCreator.onViewRecycled(holder)
        } catch (e: Exception) {
            mContext?.sendError("RecyclerAdapter: onViewRecycled", e)
        }
    }

    interface Creator {
        fun getItemCount(): Int
        fun getItemViewType(i: Int): Int
        fun onBindViewHolder(viewHolder: LuaCustRecyclerHolder, i: Int, payloads: List<Any>?)
        fun onCreateViewHolder(viewGroup: ViewGroup?, i: Int): LuaCustRecyclerHolder
        fun onViewRecycled(viewHolder: LuaCustRecyclerHolder)
    }
}

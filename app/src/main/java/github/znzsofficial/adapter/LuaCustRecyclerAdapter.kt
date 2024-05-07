package github.znzsofficial.adapter

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaContext

open class LuaCustRecyclerAdapter : RecyclerView.Adapter<LuaCustRecyclerHolder> {
    open lateinit var adapterCreator: Creator
    var mContext: LuaContext?

    constructor(creator: Creator) {
        adapterCreator = creator
        mContext = null
    }

    constructor(context: LuaContext, creator: Creator) {
        adapterCreator = creator
        mContext = context
    }

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
            LuaCustRecyclerHolder(null)
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
        abstract fun <View> getPopupText(view: View, position: Int): Any
    }
}

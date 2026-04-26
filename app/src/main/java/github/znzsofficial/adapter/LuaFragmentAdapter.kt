package github.znzsofficial.adapter

import androidx.fragment.app.Fragment
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.androlua.LuaActivity

class LuaFragmentAdapter(context: LuaActivity, inter: Creator) :
    FragmentStateAdapter(context.supportFragmentManager, context.lifecycle) {

    var creator: Creator = inter
    private val mContext: LuaActivity = context

    override fun createFragment(position: Int): Fragment {
        return try {
            // 根据位置返回对应的 Fragment
            creator.createFragment(position)
        } catch (e: Exception) {
            mContext.sendError("FragmentAdapter", e)
            Fragment()
        }
    }

    override fun getItemCount(): Int {
        return try {
            // 返回 Fragment 的数量
            creator.getItemCount().coerceAtLeast(0)
        } catch (e: Exception) {
            mContext.sendError("FragmentAdapter", e)
            0
        }
    }

    override fun getItemId(position: Int): Long {
        return try {
            (creator as? StableIdCreator)?.getItemId(position) ?: super.getItemId(position)
        } catch (e: Exception) {
            mContext.sendError("FragmentAdapter", e)
            super.getItemId(position)
        }
    }

    override fun containsItem(itemId: Long): Boolean {
        return try {
            (creator as? StableIdCreator)?.containsItem(itemId) ?: super.containsItem(itemId)
        } catch (e: Exception) {
            mContext.sendError("FragmentAdapter", e)
            super.containsItem(itemId)
        }
    }

    override fun getItemViewType(position: Int): Int {
        return try {
            (creator as? ViewTypeCreator)?.getItemViewType(position) ?: super.getItemViewType(position)
        } catch (e: Exception) {
            mContext.sendError("FragmentAdapter", e)
            super.getItemViewType(position)
        }
    }

    fun reload() {
        notifyDataSetChanged()
    }

    fun reloadItem(position: Int) {
        notifyItemChanged(position)
    }

    fun changed(position: Int, count: Int) {
        notifyItemRangeChanged(position, count.coerceAtLeast(0))
    }

    fun inserted(position: Int, count: Int) {
        notifyItemRangeInserted(position, count.coerceAtLeast(0))
    }

    fun removed(position: Int, count: Int) {
        notifyItemRangeRemoved(position, count.coerceAtLeast(0))
    }

    fun moved(fromPosition: Int, toPosition: Int) {
        notifyItemMoved(fromPosition, toPosition)
    }

    interface Creator {
        fun createFragment(i: Int): Fragment
        fun getItemCount(): Int
    }

    interface StableIdCreator : Creator {
        fun getItemId(i: Int): Long
        fun containsItem(id: Long): Boolean
    }

    interface ViewTypeCreator : Creator {
        fun getItemViewType(i: Int): Int
    }
}

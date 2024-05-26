package github.znzsofficial.adapter

import android.animation.Animator
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import jp.wasabeef.recyclerview.animators.holder.AnimateViewHolder

class AnimateRecyclerHolder(itemView: View, var creator: Creator) :
    LuaCustRecyclerHolder(itemView), AnimateViewHolder {
    override fun animateAddImpl(
        holder: RecyclerView.ViewHolder,
        listener: Animator.AnimatorListener
    ) {
        creator.animateAddImpl(holder, listener)
        // 具体的添加动画逻辑
    }

    override fun animateRemoveImpl(
        holder: RecyclerView.ViewHolder, listener: Animator.AnimatorListener
    ) {
        creator.animateRemoveImpl(holder, listener)
        // 具体的移除动画逻辑
    }

    override fun preAnimateAddImpl(holder: RecyclerView.ViewHolder) {
        creator.preAnimateAddImpl(holder)
        // 添加动画之前的准备逻辑
    }

    override fun preAnimateRemoveImpl(holder: RecyclerView.ViewHolder) {
        creator.preAnimateRemoveImpl(holder)
        // 移除动画之前的准备逻辑
    }

    interface Creator {
        fun animateAddImpl(holder: RecyclerView.ViewHolder?, listener: Animator.AnimatorListener?)
        fun animateRemoveImpl(
            holder: RecyclerView.ViewHolder?,
            listener: Animator.AnimatorListener?
        )

        fun preAnimateAddImpl(holder: RecyclerView.ViewHolder?)
        fun preAnimateRemoveImpl(holder: RecyclerView.ViewHolder?)
    }
}

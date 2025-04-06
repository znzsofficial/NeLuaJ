package github.znzsofficial.adapter

import android.view.View
import com.androlua.LuaContext
import me.zhanghai.android.fastscroll.PopupTextProvider

class PopupRecyclerAdapter @JvmOverloads constructor(
    override var mContext: LuaContext? = null,
    private val adapterCreator: PopupCreator
) : LuaCustRecyclerAdapter(mContext, adapterCreator), PopupTextProvider {

    override fun getPopupText(view: View, position: Int): CharSequence {
        return try {
            this.adapterCreator.getPopupText(view, position)
        }catch (e: Exception){
            mContext?.sendError("PopupRecyclerAdapter: getPopupText", e)
            ""
        }
    }

    interface PopupCreator : Creator {
        fun getPopupText(view: View, i: Int): CharSequence
    }
}

package github.znzsofficial.adapter

import android.view.View
import com.androlua.LuaContext
import me.zhanghai.android.fastscroll.PopupTextProvider

class PopupRecyclerListAdapter : RecyclerListAdapter, PopupTextProvider {
    override var adapterCreator: Creator

    constructor(adapterCreator: PopupCreator) : super(adapterCreator) {
        this.adapterCreator = adapterCreator
        mContext = null
    }

    constructor(context: LuaContext, adapterCreator: PopupCreator) : super(
        context,
        adapterCreator
    ) {
        this.adapterCreator = adapterCreator
        mContext = context
    }

    override fun getPopupText(view: View,position: Int): CharSequence {
        return this.adapterCreator.getPopupText(view, position).toString()
    }

    interface PopupCreator : Creator {
        override fun getPopupText(view: View, i: Int): CharSequence
    }

}

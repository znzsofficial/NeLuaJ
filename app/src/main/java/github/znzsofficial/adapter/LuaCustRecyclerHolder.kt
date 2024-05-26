package github.znzsofficial.adapter

import android.view.View
import androidx.recyclerview.widget.RecyclerView

open class LuaCustRecyclerHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
    var views: Any? = null

    fun setTag(tag:Any){
        views = tag
    }
    fun getTag() = views
}

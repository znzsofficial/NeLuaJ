package com.nekolaska.internal

import android.view.View
import android.widget.TextView
import coil3.util.CoilUtils
import com.nekolaska.ktx.toLuaValue
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable

class FileItemHolder(itemView: View) : LuaCustRecyclerHolder(itemView) {
    init {
        Tag = LuaTable()
    }

    fun bind() = Tag.apply {
        set("contents", itemView.findViewById<View>(R.id.item_contents).toLuaValue())
        set("name", itemView.findViewById<View>(R.id.item_name).toLuaValue())
    }


    fun unbind() = Tag.clear()
}
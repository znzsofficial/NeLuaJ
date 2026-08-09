package com.nekolaska.internal

import android.view.View
import com.nekolaska.ktx.toLuaInstance
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable

class FileItemHolder(itemView: View) : LuaCustRecyclerHolder(itemView) {
    init {
        Tag = LuaTable()
    }

    fun bind(): LuaTable = Tag.apply {
        set("contents", itemView.findViewById<View>(R.id.item_contents).toLuaInstance())
        set("name", itemView.findViewById<View>(R.id.item_name).toLuaInstance())
        set("check", itemView.findViewById<View>(R.id.item_check).toLuaInstance())
    }

    fun unbind() = Tag.clear()
}

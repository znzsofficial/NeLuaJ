package com.nekolaska.internal

import android.view.View
import com.nekolaska.toLuaValue
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable

class FileItemHolder(itemView: View) : LuaCustRecyclerHolder(itemView) {

    fun bind(): LuaTable {
        views = LuaTable().apply {
            set("contents", itemView.findViewById<View>(R.id.contents).toLuaValue())
            set("name", itemView.findViewById<View>(R.id.name).toLuaValue())
            set("icon", itemView.findViewById<View>(R.id.icon).toLuaValue())
        }
        return views as LuaTable
    }

    fun unbind() {
        views = null
    }
}
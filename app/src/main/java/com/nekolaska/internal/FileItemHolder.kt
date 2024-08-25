package com.nekolaska.internal

import android.view.View
import com.nekolaska.toLuaValue
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable
import org.luaj.LuaValue

class FileItemHolder(itemView: View) : LuaCustRecyclerHolder(itemView) {
    val Tag = LuaTable()
    fun bind(): LuaTable {
        return Tag.apply {
            set("contents", itemView.findViewById<View>(R.id.contents).toLuaValue())
            set("name", itemView.findViewById<View>(R.id.name).toLuaValue())
            set("icon", itemView.findViewById<View>(R.id.icon).toLuaValue())
        }
    }


    fun unbind() {
        Tag.apply {
            set("contents", LuaValue.NIL)
            set("name", LuaValue.NIL)
            set("icon", LuaValue.NIL)
        }
    }
}
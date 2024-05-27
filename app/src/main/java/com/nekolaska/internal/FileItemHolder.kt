package com.nekolaska.internal

import android.view.View
import android.widget.LinearLayout
import com.google.android.material.textview.MaterialTextView
import com.nekolaska.toLuaValue
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import github.znzsofficial.neluaj.R
import org.luaj.LuaTable

class FileItemHolder(itemView: View) : LuaCustRecyclerHolder(itemView) {

    fun bind(): LuaTable {
        views = LuaTable().apply {
            set("contents", itemView.findViewById<LinearLayout>(R.id.contents).toLuaValue())
            set("name", itemView.findViewById<MaterialTextView>(R.id.name).toLuaValue())
            set("icon", itemView.findViewById<MaterialTextView>(R.id.icon).toLuaValue())
        }
        return views as LuaTable
    }

    fun unbind() {
        views = null
    }
}
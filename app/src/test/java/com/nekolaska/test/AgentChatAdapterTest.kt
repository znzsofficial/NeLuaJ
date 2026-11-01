package com.nekolaska.test

import com.nekolaska.agent.adapter.AgentChatAdapter
import github.znzsofficial.adapter.LuaCustRecyclerHolder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.luaj.LuaTable
import org.luaj.LuaValue
import android.view.ViewGroup
import android.widget.TextView

class AgentChatAdapterTest {

    @Test
    fun testAdapterSubmitMessagesAndDiff() {
        val delegate = object : AgentChatAdapter.Delegate {
            override fun getItemViewType(item: LuaValue, position: Int): Int {
                return if (item["role"].tojstring() == "user") 0 else 1
            }

            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LuaCustRecyclerHolder {
                val tv = TextView(parent.context)
                return LuaCustRecyclerHolder(tv)
            }

            override fun onBindViewHolder(holder: LuaCustRecyclerHolder, item: LuaValue, position: Int) {
                (holder.itemView as? TextView)?.text = item["content"].tojstring()
            }
        }

        val adapter = AgentChatAdapter(null, delegate)
        assertNotNull(adapter)

        val messages = LuaTable()
        val m1 = LuaTable()
        m1["id"] = LuaValue.valueOf("1")
        m1["role"] = LuaValue.valueOf("user")
        m1["content"] = LuaValue.valueOf("hello")
        messages[1] = m1

        adapter.submitMessages(messages)
        assertEquals(1, adapter.itemCount)
        assertEquals("hello", adapter.getItem(0)?.get("content")?.tojstring())
    }
}

package com.nekolaska.test

import androidx.recyclerview.widget.ListUpdateCallback
import com.nekolaska.agent.adapter.AgentCardList
import com.nekolaska.agent.adapter.AgentChatAdapter
import org.junit.Assert.*
import org.junit.Test
import org.luaj.LuaTable
import org.luaj.LuaValue

class AgentChatAdapterTest {
    private class Updates : ListUpdateCallback {
        var inserted = 0
        var removed = 0
        val changed = mutableListOf<Any?>()
        override fun onInserted(position: Int, count: Int) { inserted += count }
        override fun onRemoved(position: Int, count: Int) { removed += count }
        override fun onMoved(fromPosition: Int, toPosition: Int) = Unit
        override fun onChanged(position: Int, count: Int, payload: Any?) { changed += payload }
    }

    private fun card(id: String, type: Int = 1, text: String = "hello") = LuaTable().apply {
        set("stableId", LuaValue.valueOf(id))
        set("viewType", LuaValue.valueOf(type))
        set(if (type == 4) "text" else "content", LuaValue.valueOf(text))
        if (type == 4) set("streamId", LuaValue.valueOf(1))
    }

    @Test fun appendDoesNotRebindUnchangedCards() {
        val cards = AgentCardList()
        val first = card("first")
        cards.replace(listOf(first))
        val updates = Updates()
        cards.replace(listOf(first, card("second"))).dispatchUpdatesTo(updates)
        assertEquals(1, updates.inserted)
        assertTrue(updates.changed.isEmpty())
        val empty = Updates()
        cards.replace(emptyList()).dispatchUpdatesTo(empty)
        assertEquals(2, empty.removed)
        assertEquals(0, cards.size)
    }

    @Test fun streamUpdatesPersistForRebindingAndUsePayloads() {
        val cards = AgentCardList()
        cards.replace(listOf(card("stream", 4, "a")))
        val updates = Updates()
        cards.replace(listOf(card("stream", 4, "ab"))).dispatchUpdatesTo(updates)
        assertEquals(listOf(AgentChatAdapter.PAYLOAD_STREAMING_TEXT), updates.changed)
        assertEquals(0, cards.updateStream("1", "abc"))
        assertEquals("abc", cards[0].get("text").tojstring())
        assertEquals(-1, cards.updateStream("old-stream", "stale"))
        assertEquals("abc", cards[0].get("text").tojstring())
    }

    @Test fun mutableMessageMetadataIsComparedAgainstSnapshot() {
        val cards = AgentCardList()
        val first = card("first")
        val message = LuaTable().apply { set("continuation_state", LuaValue.valueOf("stopped")) }
        first.set("message", message)
        cards.replace(listOf(first))
        message.set("continuation_state", LuaValue.NIL)
        val updates = Updates()
        cards.replace(listOf(first)).dispatchUpdatesTo(updates)
        assertEquals(1, updates.changed.size)
        assertNull(updates.changed.single())
    }
}

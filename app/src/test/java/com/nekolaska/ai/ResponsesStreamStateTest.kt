package com.nekolaska.ai

import org.junit.Assert.assertEquals
import org.junit.Test

class ResponsesStreamStateTest {
    @Test
    fun delayedCallIdRetainsArgumentsAndNativeOutputOrder() {
        val state = ResponsesStreamState()
        state.recordOutput(1, "fc_b", "{\"id\":\"fc_b\"}")
        state.appendArguments("", "fc_b", 1, "{\"b\":2}")
        state.recordOutput(0, "fc_a", "{\"id\":\"fc_a\"}")
        state.appendArguments("", "fc_a", 0, "{\"a\":1}")
        state.completeFunctionCall("call_b", "fc_b", 1, "second", "{\"b\":2}")
        state.completeFunctionCall("call_a", "fc_a", 0, "first", "{\"a\":1}")

        val calls = state.toolCalls()
        assertEquals(2, calls.size)
        assertEquals("call_a", calls[0].id)
        assertEquals("{\"a\":1}", calls[0].arguments)
        assertEquals("call_b", calls[1].id)
        assertEquals("{\"b\":2}", calls[1].arguments)

        val output = state.responseOutput()
        assertEquals(2, output.size)
        assertEquals("{\"id\":\"fc_a\"}", output[0])
        assertEquals("{\"id\":\"fc_b\"}", output[1])
    }

    @Test
    fun completedOutputSupersedesPartialSseItems() {
        val state = ResponsesStreamState()
        state.recordOutput(0, "partial", "{\"id\":\"partial\"}")
        state.setCompletedOutput(listOf("{\"id\":\"reasoning\"}", "{\"id\":\"message\"}"))

        assertEquals(
            listOf("{\"id\":\"reasoning\"}", "{\"id\":\"message\"}"),
            state.responseOutput()
        )
    }

    @Test
    fun blankChatToolNameDoesNotEraseEarlierName() {
        assertEquals("read_file", keepExistingWhenBlank("read_file", ""))
        assertEquals("write_file", keepExistingWhenBlank("read_file", "write_file"))
    }
}

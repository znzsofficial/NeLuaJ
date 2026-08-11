package com.nekolaska.ai

internal data class ResponsesToolCall(
    val id: String,
    val itemId: String?,
    val name: String,
    val arguments: String,
    val outputIndex: Int?
)

internal fun keepExistingWhenBlank(existing: String, incoming: String): String =
    if (incoming.isEmpty()) existing else incoming

/**
 * Correlates Responses SSE fragments without depending on Android's org.json
 * implementation so the same state transitions can be covered by unit tests.
 */
internal class ResponsesStreamState {
    private class PendingToolCall {
        var callId = ""
        var itemId = ""
        var outputIndex: Int? = null
        var name = ""
        var arguments = ""
    }

    private val callsByCallId = linkedMapOf<String, PendingToolCall>()
    private val callsByItemId = linkedMapOf<String, PendingToolCall>()
    private val outputIndexesByItemId = mutableMapOf<String, Int>()
    private val fallbackOutput = sortedMapOf<Int, String>()
    private var completedOutput: List<String>? = null
    private var nextOutputIndex = 0

    fun recordOutput(outputIndex: Int?, itemId: String, encodedItem: String) {
        val index = outputIndex
            ?: outputIndexesByItemId[itemId]
            ?: nextOutputIndex
        nextOutputIndex = maxOf(nextOutputIndex, index + 1)
        fallbackOutput[index] = encodedItem
        if (itemId.isNotEmpty()) outputIndexesByItemId[itemId] = index
    }

    private fun merge(target: PendingToolCall, source: PendingToolCall) {
        if (target.callId.isEmpty()) target.callId = source.callId
        if (target.itemId.isEmpty()) target.itemId = source.itemId
        if (target.outputIndex == null) target.outputIndex = source.outputIndex
        if (target.name.isEmpty()) target.name = source.name
        if (target.arguments.isEmpty()) target.arguments = source.arguments
        callsByCallId.entries.filter { it.value === source }.forEach { it.setValue(target) }
        callsByItemId.entries.filter { it.value === source }.forEach { it.setValue(target) }
    }

    private fun resolve(callId: String, itemId: String, outputIndex: Int?): PendingToolCall? {
        if (callId.isEmpty() && itemId.isEmpty()) return null
        val byCallId = callId.takeIf { it.isNotEmpty() }?.let(callsByCallId::get)
        val byItemId = itemId.takeIf { it.isNotEmpty() }?.let(callsByItemId::get)
        val call = when {
            byCallId != null && byItemId != null && byCallId !== byItemId -> {
                merge(byCallId, byItemId)
                byCallId
            }
            byCallId != null -> byCallId
            byItemId != null -> byItemId
            else -> PendingToolCall()
        }
        if (callId.isNotEmpty()) {
            call.callId = callId
            callsByCallId[callId] = call
        }
        if (itemId.isNotEmpty()) {
            call.itemId = itemId
            callsByItemId[itemId] = call
        }
        if (outputIndex != null) call.outputIndex = outputIndex
        return call
    }

    fun appendArguments(callId: String, itemId: String, outputIndex: Int?, delta: String) {
        resolve(callId, itemId, outputIndex)?.let { it.arguments += delta }
    }

    fun setArguments(callId: String, itemId: String, outputIndex: Int?, arguments: String?) {
        resolve(callId, itemId, outputIndex)?.let { call ->
            if (arguments != null) call.arguments = arguments
        }
    }

    fun observeFunctionCall(
        callId: String,
        itemId: String,
        outputIndex: Int?,
        name: String?,
        arguments: String?
    ) {
        val call = resolve(callId, itemId, outputIndex) ?: return
        if (!name.isNullOrEmpty()) call.name = name
        if (!arguments.isNullOrEmpty()) call.arguments = arguments
    }

    fun completeFunctionCall(
        callId: String,
        itemId: String,
        outputIndex: Int?,
        name: String?,
        arguments: String?
    ) {
        if (callId.isEmpty()) return
        observeFunctionCall(
            callId,
            itemId,
            outputIndexesByItemId[itemId] ?: outputIndex,
            name,
            arguments
        )
    }

    fun setCompletedOutput(items: List<String>) {
        completedOutput = items
    }

    fun toolCalls(): List<ResponsesToolCall> = callsByCallId.values
        .distinct()
        .filter { it.callId.isNotEmpty() && it.name.isNotEmpty() }
        .sortedBy { it.outputIndex ?: Int.MAX_VALUE }
        .map {
            ResponsesToolCall(
                id = it.callId,
                itemId = it.itemId.ifEmpty { null },
                name = it.name,
                arguments = it.arguments,
                outputIndex = it.outputIndex
            )
        }

    fun responseOutput(): List<String> = completedOutput ?: fallbackOutput.values.toList()
}

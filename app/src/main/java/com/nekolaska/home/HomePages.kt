package com.nekolaska.home

/** Persisted identities: never derive these from translated labels or the current menu order. */
object HomePages {
    private val keys = listOf("projects", "conversations", "help", "settings")
    private val ids = listOf(0x4e4c0001L, 0x4e4c0002L, 0x4e4c0003L, 0x4e4c0004L)

    @JvmStatic fun count(): Int = keys.size
    @JvmStatic fun keyAt(position: Int): String = keys[position]
    @JvmStatic fun idAt(position: Int): Long = ids[position]
    @JvmStatic fun positionOf(key: String): Int = keys.indexOf(key)
    @JvmStatic fun containsId(id: Long): Boolean = id in ids
    @JvmStatic fun useRail(widthPx: Int, density: Float): Boolean =
        density > 0 && widthPx / density >= 600f
}

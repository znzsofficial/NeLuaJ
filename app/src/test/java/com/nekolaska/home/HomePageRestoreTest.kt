package com.nekolaska.home

import org.junit.Assert.*
import org.junit.Test

/** Pure production policy tests; actual FragmentManager recreation still needs Android. */
class HomePageRestoreTest {
    @Test fun persistedIdentitiesAreUniqueAndNotLocalized() {
        val keys = (0 until HomePages.count()).map(HomePages::keyAt)
        val ids = (0 until HomePages.count()).map(HomePages::idAt)
        assertEquals(listOf("projects", "conversations", "help", "settings"), keys)
        assertEquals(keys.size, keys.toSet().size)
        assertEquals(ids.size, ids.toSet().size)
        keys.forEachIndexed { index, key ->
            assertEquals(index, HomePages.positionOf(key))
            assertTrue(HomePages.containsId(HomePages.idAt(index)))
        }
        assertEquals(-1, HomePages.positionOf("项目"))
        assertFalse(HomePages.containsId(-1L))
    }

    @Test fun identityValuesRemainCompatibleWithSavedState() {
        assertEquals(0x4e4c0001L, HomePages.idAt(0))
        assertEquals(0x4e4c0002L, HomePages.idAt(1))
        assertEquals(0x4e4c0003L, HomePages.idAt(2))
        assertEquals(0x4e4c0004L, HomePages.idAt(3))
    }

    @Test fun actualWindowWidthRatherThanDeviceOrOrientationSelectsRail() {
        assertFalse(HomePages.useRail(1199, 2f))
        assertTrue(HomePages.useRail(1200, 2f))
        assertTrue(HomePages.useRail(1800, 3f))
        assertFalse(HomePages.useRail(500, 1f))
        assertFalse(HomePages.useRail(0, 3f))
        assertFalse(HomePages.useRail(1800, 0f))
    }
}

package com.androlua.layout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class LayoutReflectionTest {

    open class Base {
        fun publicBaseMethod() {}
    }

    class Child : Base() {
        fun publicChildMethod() {}
    }

    @Test
    fun cachedMethodFindsMethodsOnSelfAndHierarchy() {
        val cache = LayoutReflection.objectSetterCache()
        val childMethod = LayoutReflection.cachedMethod(cache, Child::class.java, "publicChildMethod")
        assertNotNull(childMethod)
        assertEquals("publicChildMethod", childMethod?.name)

        val baseMethod = LayoutReflection.cachedMethod(cache, Child::class.java, "publicBaseMethod")
        assertNotNull(baseMethod)
        assertEquals("publicBaseMethod", baseMethod?.name)

        val missing = LayoutReflection.cachedMethod(cache, Child::class.java, "nonExistentMethod")
        assertNull(missing)
    }
}

package com.nekolaska.test

class KotlinDirectTest {
    companion object {
        @JvmStatic
        fun executeKotlinDirect(block: (String) -> Unit): String {
            val u = block("Hello from Real Kotlin")
            return "Kotlin executed ok, unit: $u"
        }
    }
}

package org.luaj.lib.jse

object KotlinObjectFixture {
    val label = "object"

    fun greet(name: String): String = "object:$name"

    fun sequence(): Sequence<String> = sequenceOf("first", "second")
}

class KotlinCompanionFixture {
    companion object {
        val label = "companion"

        fun greet(name: String): String = "companion:$name"

        @JvmStatic
        fun staticGreet(name: String): String = "static:$name"
    }
}

package com.nekolaska.ktx

import kotlinx.coroutines.suspendCancellableCoroutine
import org.luaj.Globals
import org.luaj.LuaString
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.jse.CoerceJavaToLua
import org.luaj.lib.jse.CoerceLuaToJava
import org.luaj.lib.jse.JavaInstance
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.jvm.javaObjectType

@Suppress("NOTHING_TO_INLINE")
inline fun String.toLuaString(): LuaValue = this.toByteArray(Charsets.UTF_8).let {
    LuaString.valueUsing(it, 0, it.size)
}

@Suppress("NOTHING_TO_INLINE")
inline fun Globals.require(value: LuaValue): LuaValue = packageLib.requireFunction.call(value)

@Suppress("NOTHING_TO_INLINE")
inline fun Globals.require(module: String): LuaValue = require(LuaValue.valueOf(module))

@Suppress("NOTHING_TO_INLINE")
inline fun Varargs.firstArg(): LuaValue = this.arg1()

@Suppress("NOTHING_TO_INLINE")
inline fun Varargs.secondArg(): LuaValue = this.arg(2)

@Suppress("NOTHING_TO_INLINE")
inline fun Varargs.argAt(index: Int): LuaValue = this.arg(index)

@Suppress("NOTHING_TO_INLINE")
inline fun Varargs.asString(): String = this.tojstring()

@Suppress("NOTHING_TO_INLINE")
inline fun LuaValue.isNotNil(): Boolean = !this.isnil()

@Suppress("NOTHING_TO_INLINE")
inline fun LuaValue.ifNotNil(): LuaValue? = takeIf { it.isNotNil() }

@Suppress("NOTHING_TO_INLINE")
inline fun LuaValue.ifIsFunction(): LuaValue? = takeIf { it.isfunction() }

@Suppress("unused")
suspend fun LuaValue.suspendInvoke(varargs: Varargs): Varargs = suspendCancellableCoroutine {
    try {
        it.resume(this.invoke(varargs))
    } catch (e: Exception) {
        it.resumeWithException(e)
    }
}

@Suppress("NOTHING_TO_INLINE")
inline fun Any?.toLuaValue(): LuaValue = CoerceJavaToLua.coerce(this)

@Suppress("NOTHING_TO_INLINE")
inline fun <T> T.toLuaInstance(): LuaValue = JavaInstance(this)
//@Suppress("NOTHING_TO_INLINE", "unused")
//inline fun <T> LuaValue.toAny(clazz: Class<T>): Any = CoerceLuaToJava.coerce(this, clazz)

//inline fun <reified T : Any> KClass<T>.toLuaClass(): LuaValue = CoerceJavaToLua.coerce(this.java)
private fun LuaValue.invokeLuaArguments(arguments: Array<out Any?>): Varargs =
    invoke(Array(arguments.size) { arguments[it].toLuaValue() })

fun LuaValue.invokeLua(vararg arguments: Any?): Varargs = invokeLuaArguments(arguments)

@Suppress("unused")
fun LuaValue.callLua(vararg arguments: Any?): LuaValue = invokeLuaArguments(arguments).arg1()

inline fun <reified T : Any> LuaValue.toJavaOrNull(): T? {
    if (isnil()) return null
    @Suppress("UNCHECKED_CAST")
    return CoerceLuaToJava.coerce(this, T::class.javaObjectType) as T
}

inline fun <reified T : Any> LuaValue.requireJava(): T =
    toJavaOrNull<T>() ?: error("expected ${T::class.java.name}, got nil")

fun <T> Array<T>.toVarargs(): Varargs =
    LuaValue.varargsOf(Array(size) { this[it].toLuaValue() })

fun <T> List<T>.toVarargs(): Varargs =
    LuaValue.varargsOf(Array(size) { this[it].toLuaValue() })

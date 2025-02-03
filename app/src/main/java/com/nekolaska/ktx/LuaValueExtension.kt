package com.nekolaska.ktx

import kotlinx.coroutines.suspendCancellableCoroutine
import org.luaj.Globals
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.jse.CoerceJavaToLua
import org.luaj.lib.jse.JavaInstance
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException


//package_.require.call(v)
@Suppress("NOTHING_TO_INLINE")
inline fun Globals.require(value: LuaValue): LuaValue = this.p.y.call(value)

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
inline fun <T> T.toLuaValue(): LuaValue = CoerceJavaToLua.coerce(this)

@Suppress("NOTHING_TO_INLINE")
inline fun <T> T.toLuaInstance(): LuaValue = JavaInstance(this)
//@Suppress("NOTHING_TO_INLINE", "unused")
//inline fun <T> LuaValue.toAny(clazz: Class<T>): Any = CoerceLuaToJava.coerce(this, clazz)

//inline fun <reified T : Any> KClass<T>.toLuaClass(): LuaValue = CoerceJavaToLua.coerce(this.java)
inline fun <reified T> Array<T>.toVarargs(): Varargs = LuaValue.varargsOf(this)

@Suppress("unused")
inline fun <reified T> ArrayList<T>.toVarargs(): Varargs = LuaValue.varargsOf(this)
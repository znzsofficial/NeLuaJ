package com.nekolaska

import kotlinx.coroutines.suspendCancellableCoroutine
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.jse.CoerceJavaToLua
import org.luaj.lib.jse.CoerceLuaToJava
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

inline fun Varargs.firstArg(): LuaValue = this.arg1()
inline fun Varargs.secondArg(): LuaValue = this.arg(2)
inline fun Varargs.argAt(index: Int): LuaValue = this.arg(index)
inline fun Varargs.asString(): String = this.tojstring()
inline fun LuaValue.isNotNil(): Boolean = !this.isnil()

inline fun LuaValue.ifNotNil(): LuaValue? = takeIf { it.isNotNil() }
inline fun LuaValue.ifIsFunction(): LuaValue? = takeIf { it.isfunction() }

suspend fun LuaValue.suspendInvoke(varargs: Varargs) = suspendCancellableCoroutine {
    try {
        it.resume(this.invoke(varargs))
    } catch (e: Exception) {
        it.resumeWithException(e)
    }
}

inline fun <T> T.toLuaValue(): LuaValue = CoerceJavaToLua.coerce(this)

inline fun <T> LuaValue.toAny(clazz: Class<T>): Any? = CoerceLuaToJava.coerce(this, clazz)

//inline fun <reified T : Any> KClass<T>.toLuaClass(): LuaValue = CoerceJavaToLua.coerce(this.java)
inline fun <reified T> Array<T>.toVarargs(): Varargs = LuaValue.varargsOf(this)
inline fun <reified T> ArrayList<T>.toVarargs(): Varargs = LuaValue.varargsOf(this)
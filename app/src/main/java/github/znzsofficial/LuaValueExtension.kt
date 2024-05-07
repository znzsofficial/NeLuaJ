package github.znzsofficial

import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.jse.CoerceJavaToLua

inline fun Varargs.firstArg(): LuaValue = this.arg1()
inline fun Varargs.secondArg(): LuaValue = this.arg(2)
inline fun Varargs.argAt(index: Int): LuaValue = this.arg(index)
inline fun Varargs.asString(): String = this.tojstring()
inline fun LuaValue.isNotNil(): Boolean = !this.isnil()

inline fun LuaValue.ifNotNil(): LuaValue? = takeIf { it.isNotNil() }
inline fun LuaValue.ifIsFunction(): LuaValue? = takeIf { it.isfunction() }

inline fun <T> T.toLuaValue(): LuaValue = CoerceJavaToLua.coerce(this)
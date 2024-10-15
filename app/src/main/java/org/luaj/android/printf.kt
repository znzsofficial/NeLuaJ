package org.luaj.android

import com.androlua.LuaContext
import com.nekolaska.ktx.format
import com.nekolaska.ktx.stringLib
import org.luaj.Globals
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction

class printf(context: LuaContext) : VarArgFunction() {
    private val mContext: LuaContext = context
    private val globals: Globals = mContext.luaState

    override fun invoke(args: Varargs?): Varargs? {
        mContext.sendMsg(globals.stringLib.format(args).tojstring())
        return NONE
    }
}
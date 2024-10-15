package org.luaj.android

import com.androlua.LuaContext
import com.nekolaska.ktx.baseLib
import com.nekolaska.ktx.tostring
import org.luaj.Globals
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction

class print(context: LuaContext) : VarArgFunction() {
    private val mContext: LuaContext = context
    private val globals: Globals = mContext.luaState

    override fun invoke(args: Varargs): Varargs? {
        val tostring: LuaValue = globals.baseLib.tostring
        val n = args.narg()

        // 使用 joinToString 函数简化拼接
        val result = (1..n).joinToString("    ") { index ->
            tostring.call(args.arg(index)).tojstring()
        }

        mContext.sendMsg(result)
        return NONE
    }

}


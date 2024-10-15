package org.luaj.android

import android.view.ViewGroup
import com.androlua.LuaContext
import com.androlua.LuaLayout
import com.nekolaska.ktx.argAt
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaValue
import org.luaj.Globals
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction

class loadlayout(context: LuaContext) : VarArgFunction() {
    private val mContext: LuaContext = context
    private val globals: Globals = mContext.luaState

    override fun invoke(args: Varargs): Varargs {
        return when (args.narg()) {
            1 -> LuaLayout(mContext.context).load(args.firstArg(), globals)
            2 -> LuaLayout(mContext.context).load(args.firstArg(), args.secondArg().checktable())
            3 -> LuaLayout(mContext.context).load(
                args.firstArg(),
                args.secondArg().checktable(),
                args.argAt(3)
            )
            else -> mContext.sendMsg("loadlayout: invalid arguments").let { NIL }
        }
    }
}

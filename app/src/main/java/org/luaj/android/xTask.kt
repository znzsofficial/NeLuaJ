package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaString
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceJavaToLua

class xTask(private val mContext: LuaActivity) : VarArgFunction(), LuaGcable {
    private var coroutine: LuaValue? = null
    override fun invoke(args: Varargs): Varargs? {
        val table = args.arg1().checktable()
        val task = table["task"]
        val callback = table["callback"]
        var result: Varargs? = null
        coroutine = CoerceJavaToLua.coerce(
            mContext.lifecycleScope.launch(
                table["dispatcher"].tojstring().let {
                    when (it) {
                        "io" -> Dispatchers.IO
                        "unconfined" -> Dispatchers.Unconfined
                        else -> Dispatchers.Default
                    }
                }
            ) {
                try {
                    if (task.isfunction()) result = task.invoke()
                } catch (e: Exception) {
                    result = LuaString.valueOf(e.message)
                    mContext.sendError("xTask: Background", e)
                }
                if (callback.isfunction())
                    try {
                        withContext(Dispatchers.Main) {
                            callback.invoke(result)
                        }
                    } catch (e: Exception) {
                        mContext.sendError("xTask: Main", e)
                    }
            }
        )
        return coroutine
    }

    override fun gc() {
        coroutine = null
    }

    override fun isGc(): Boolean {
        return coroutine == null
    }

}

package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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
        val p0 = args.arg1()
        val p1 = args.arg(2)
        val p2 = args.arg(3)
        val context = if ("io" == p2.tojstring()) {
            Dispatchers.IO
        } else {
            Dispatchers.Default
        }
        var result: Varargs? = null
        coroutine = CoerceJavaToLua.coerce(mContext.lifecycleScope.launch(context) {
            try {
                if (p0.isnumber()) delay(p0.tolong())
                else result = p0.invoke()
            } catch (e: Exception) {
                e.printStackTrace()
                result = LuaString.valueOf(e.message)
                mContext.sendError("xTask: Background", e)
            }
            if (!p1.isnil())
                try {
                    withContext(Dispatchers.Main) {
                        p1.invoke(result)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    mContext.sendError("xTask: Main", e)
                }
        })
        return coroutine
    }

    override fun gc() {
        coroutine = null
    }

    override fun isGc(): Boolean {
        return coroutine == null
    }

}

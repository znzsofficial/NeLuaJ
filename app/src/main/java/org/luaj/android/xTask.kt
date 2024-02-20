package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaString
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceJavaToLua

class xTask(private val mContext: LuaActivity) : VarArgFunction() {
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
        return CoerceJavaToLua.coerce(mContext.lifecycleScope.launch(context) {
            try {
                if (p0.isnumber()) {
                    delay(p0.tolong())
                } else {
                    result = p0.invoke()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                result = LuaString.valueOf(e.message)
                mContext.sendError("xTask: Background", e)
            }
            try {
                withContext(Dispatchers.Main) {
                    p1.invoke(result)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                mContext.sendError("xTask: Main", e)
            }
        })
    }

}

package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import com.nekolaska.asString
import com.nekolaska.firstArg
import com.nekolaska.ifIsFunction
import com.nekolaska.toLuaValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaError
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction


class xTask(private val mContext: LuaActivity) : VarArgFunction(), LuaGcable {

    private var job: LuaValue? = null

    override fun invoke(args: Varargs): Varargs? =
        args.firstArg().checktable().let { table ->
            mContext.lifecycleScope.launch {
                withContext(
                    when (table["dispatcher"].asString()) {
                        "io" -> Dispatchers.IO
                        else -> Dispatchers.Default
                    }
                ) {
                    try {
                        table["task"].ifIsFunction()?.invoke()
                    } catch (e: LuaError) {
                        mContext.sendError("xTask: Background", e)
                        NIL
                    }
                }.let { result ->
                    table["callback"].ifIsFunction()?.apply {
                        runCatching {
                            invoke(result)
                        }.onFailure {
                            mContext.sendError("xTask: Main", it as LuaError)
                        }
                    }
                }
                // 先把 job 存起来，再用 let 返回
            }.also { job = it.toLuaValue() }.let { job }
        }


    override fun gc() {
        job = null
    }

    override fun isGc(): Boolean {
        return job == null
    }

}

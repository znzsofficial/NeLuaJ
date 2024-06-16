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
import org.luaj.LuaString
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction


class xTask(private val mContext: LuaActivity) : VarArgFunction(), LuaGcable {

    private var coroutine: LuaValue? = null

    override fun invoke(args: Varargs): Varargs? =
        args.firstArg().checktable().let { table ->
            mContext.lifecycleScope.launch {
                try {
                    withContext(
                        when (table["dispatcher"].asString()) {
                            "io" -> Dispatchers.IO
                            else -> Dispatchers.Default
                        }
                    ) {
                        table["task"].ifIsFunction()?.invoke()
                    }
                } catch (e: LuaError) {
                    mContext.sendError("xTask: Background", e)
                    LuaString.valueOf(e.message)
                }.let { result ->
                    table["callback"].ifIsFunction()?.apply {
                        runCatching {
                            invoke(result)
                        }.onFailure {
                            mContext.sendError("xTask: Main", it as LuaError)
                        }
                    }
                }
                // 先把 coroutine 存起来，再用 let 返回
            }.also { coroutine = it.toLuaValue() }.let { coroutine }
        }


    override fun gc() {
        coroutine = null
    }

    override fun isGc(): Boolean {
        return coroutine == null
    }

}

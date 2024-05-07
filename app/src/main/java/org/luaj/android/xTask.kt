package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import github.znzsofficial.firstArg
import github.znzsofficial.toLuaValue
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
            mContext.lifecycleScope.launch(
                when (table["dispatcher"].tojstring()) {
                    "io" -> Dispatchers.IO
                    "unconfined" -> Dispatchers.Unconfined
                    else -> Dispatchers.Default
                }
            ) {
                try {
                    table["task"].takeIf { it.isfunction() }?.invoke()
                } catch (e: LuaError) {
                    mContext.sendError("xTask: Background", e)
                    LuaString.valueOf(e.message)
                }.let { result ->
                    table["callback"].takeIf { it.isfunction() }?.apply {
                        runCatching {
                            withContext(Dispatchers.Main) { invoke(result) }
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

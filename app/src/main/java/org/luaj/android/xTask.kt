package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import com.nekolaska.argAt
import com.nekolaska.asString
import com.nekolaska.firstArg
import com.nekolaska.ifIsFunction
import com.nekolaska.secondArg
import com.nekolaska.toLuaValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaError
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction


class xTask(private val mContext: LuaActivity) : VarArgFunction(), LuaGcable {

    private var job: Job? = null

    override fun invoke(args: Varargs): Varargs =
        args.firstArg().run {
            if (isfunction()) mContext.lifecycleScope.launch {
                withContext(
                    when (args.argAt(3).asString()) {
                        "io" -> Dispatchers.IO
                        else -> Dispatchers.Default
                    }
                ) {
                    try {
                        call(coroutineContext.toLuaValue())
                    } catch (e: LuaError) {
                        mContext.sendError("xTask: Background", e)
                        NIL
                    }
                }.let { result ->
                    args.secondArg().ifIsFunction()?.apply {
                        runCatching {
                            invoke(result)
                        }.onFailure {
                            mContext.sendError("xTask: Main", it as LuaError)
                        }
                    }
                }
                // 先把 job 存起来，再用 let 返回
            }.also { job = it }.let { job.toLuaValue() }
            else checktable().let { table ->
                mContext.lifecycleScope.launch {
                    withContext(
                        when (table["dispatcher"].asString()) {
                            "io" -> Dispatchers.IO
                            else -> Dispatchers.Default
                        }
                    ) {
                        try {
                            table["task"].ifIsFunction()?.call(coroutineContext.toLuaValue())
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
                }.also { job = it }.let { job.toLuaValue() }
            }
        }

    override fun gc() {
        job?.cancel()
        job = null
    }

    override fun isGc(): Boolean {
        return job == null
    }

}

package org.luaj.android

import androidx.lifecycle.lifecycleScope
import com.androlua.LuaActivity
import com.androlua.LuaGcable
import com.nekolaska.ktx.argAt
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.ifIsFunction
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction

class LuaJobWrapper(var job: Job?) : LuaGcable {
    override fun gc() {
        job?.cancel()
        job = null
    }

    override fun isGc(): Boolean {
        return job == null || (job?.isCompleted == true)
    }

    fun toLuaValue(): LuaValue {
        return org.luaj.lib.jse.CoerceJavaToLua.coerce(this)
    }
}

class xTask(private val mContext: LuaActivity) : VarArgFunction() {

    override fun invoke(args: Varargs): Varargs =
        args.firstArg().run {
            if (isfunction()) {
                val job = mContext.lifecycleScope.launch {
                    val result = withContext(
                        when (args.argAt(3).asString()) {
                            "io" -> Dispatchers.IO
                            else -> Dispatchers.Default
                        }
                    ) {
                        try {
                            invoke(coroutineContext.toLuaValue())
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            mContext.sendError("xTask: Background", e)
                            NIL
                        }
                    }
                    args.secondArg().ifIsFunction()?.apply {
                        runCatching {
                            invoke(result)
                        }.onFailure {
                            mContext.sendError("xTask: Main", it as Exception)
                        }
                    }
                }
                LuaJobWrapper(job).toLuaValue()
            } else checktable().let { table ->
                val job = mContext.lifecycleScope.launch {
                    val result = withContext(
                        when (table["dispatcher"].asString()) {
                            "io" -> Dispatchers.IO
                            else -> Dispatchers.Default
                        }
                    ) {
                        try {
                            table["task"].ifIsFunction()?.call(coroutineContext.toLuaValue()) ?: NIL
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            mContext.sendError("xTask: Background", e)
                            NIL
                        }
                    }
                    table["callback"].ifIsFunction()?.apply {
                        runCatching {
                            invoke(result)
                        }.onFailure {
                            mContext.sendError("xTask: Main", it as Exception)
                        }
                    }
                }
                LuaJobWrapper(job).toLuaValue()
            }
        }
}

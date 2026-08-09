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
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction

class LuaJobWrapper(@Volatile var job: Job?) : LuaGcable {
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

    fun cancel() = gc()

    fun isActive(): Boolean = job?.isActive == true
}

class xTask(private val mContext: LuaActivity) : VarArgFunction() {

    override fun invoke(args: Varargs): Varargs {
        val first = args.firstArg()
        return if (first.isfunction()) {
            launchTask(
                task = first,
                callback = args.secondArg().ifIsFunction(),
                dispatcher = dispatcherFor(args.argAt(3)),
                preserveTaskVarargs = true
            )
        } else {
            val table = first.checktable()
            launchTask(
                task = table["task"].ifIsFunction(),
                callback = table["callback"].ifIsFunction(),
                dispatcher = dispatcherFor(table["dispatcher"]),
                preserveTaskVarargs = false
            )
        }
    }

    private fun launchTask(
        task: LuaValue?,
        callback: LuaValue?,
        dispatcher: CoroutineDispatcher,
        preserveTaskVarargs: Boolean
    ): LuaValue {
        val job = mContext.lifecycleScope.launch(dispatcher) {
            val result = try {
                val context = coroutineContext.toLuaValue()
                when {
                    task == null -> NIL
                    preserveTaskVarargs -> task.invoke(context)
                    else -> task.call(context)
                }
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                reportError("xTask: Background", exception)
                NIL
            }

            if (callback != null) {
                withContext(Dispatchers.Main.immediate) {
                    try {
                        callback.invoke(result)
                    } catch (exception: CancellationException) {
                        throw exception
                    } catch (exception: Exception) {
                        mContext.sendError("xTask: Main", exception)
                    }
                }
            }
        }
        return LuaJobWrapper(job).toLuaValue()
    }

    private suspend fun reportError(title: String, exception: Exception) {
        withContext(Dispatchers.Main.immediate) {
            mContext.sendError(title, exception)
        }
    }

    private fun dispatcherFor(value: LuaValue): CoroutineDispatcher = when (value.asString()) {
        "io" -> Dispatchers.IO
        else -> Dispatchers.Default
    }
}

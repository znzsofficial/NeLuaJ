package com.nekolaska.io

import android.os.Handler
import android.os.Looper
import android.util.Log
import org.luaj.LuaValue
import java.util.concurrent.Executors

/** Transactions own process-wide tokens, so their workers must outlive an Activity.
 * Cancellation is cooperative in FileMutationService, never cancellation of this queue.
 * Completion is best-effort UI delivery; the worker has already settled/released.
 */
object FileMutationDispatcher {
    private val workers = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "file-mutations").apply { isDaemon = true }
    }

    @JvmStatic fun submit(work: LuaValue, done: LuaValue) {
        workers.execute {
            val result = try { work.call() }
            catch (error: Exception) {
                Log.e("FileMutationDispatcher", "Transaction worker failed", error)
                LuaValue.NIL
            }
            Handler(Looper.getMainLooper()).post {
                try { done.call(result) }
                catch (error: Exception) { Log.e("FileMutationDispatcher", "Completion failed", error) }
            }
        }
    }
}

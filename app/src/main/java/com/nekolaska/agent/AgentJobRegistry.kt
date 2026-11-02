package com.nekolaska.agent

import org.luaj.android.LuaJobWrapper

/**
 * 线程安全的后台工具并发任务注册表。
 * 支持批量任务追踪、全量原子取消与清理，杜绝单例被覆盖导致的脱缰后台任务。
 *
 * 与工程现有 org.luaj.android.LuaJobWrapper / xTask 强类型深度对齐，
 * 避免无谓反射，纳秒级直接执行 cancel()。
 */
object AgentJobRegistry {

    private val lock = Any()
    private val activeJobs = LinkedHashMap<Any, String>()

    @JvmStatic
    fun register(job: Any?, toolName: String?) {
        if (job == null || toolName == null) return
        synchronized(lock) { activeJobs[job] = toolName }
    }

    @JvmStatic
    fun unregister(job: Any?) {
        if (job == null) return
        synchronized(lock) { activeJobs.remove(job) }
    }

    /**
     * 原子级全量取消所有正在执行的后台任务，并返回被取消的工具名称列表。
     * 直接解包 LuaJobWrapper 强类型，消除 JNI 反射开销。
     */
    @JvmStatic
    fun cancelAll(): List<String> {
        // Atomically detach one batch. Jobs registered during cancellation
        // belong to the next batch and must remain tracked. Never run user
        // cancellation code while holding the registry lock.
        val batch = synchronized(lock) {
            activeJobs.toMap().also { activeJobs.clear() }
        }
        val cancelledTools = ArrayList<String>(batch.size)
        batch.forEach { (job, toolName) ->
            try {
                if (job is LuaJobWrapper) {
                    job.cancel()
                } else {
                    val cancelMethod = job.javaClass.methods.firstOrNull {
                        it.name == "cancel" && it.parameterCount == 0
                    }
                    cancelMethod?.let {
                        it.isAccessible = true
                        it.invoke(job)
                    }
                }
            } catch (_: Throwable) {}
            cancelledTools.add(toolName)
        }
        return cancelledTools
    }

    @JvmStatic
    fun activeCount(): Int = synchronized(lock) { activeJobs.size }
}

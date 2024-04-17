package org.luaj.android

import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.luaj.Globals
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.VarArgFunction
import org.luaj.lib.jse.CoerceJavaToLua


class okhttp : TwoArgFunction() {
    private lateinit var globals: Globals
    private val client = OkHttpClient.Builder().build()
    override fun call(modname: LuaValue, env: LuaValue): LuaValue {
        globals = env.checkglobals()
        val okhttp = LuaTable().apply {
            set("get", get())
            set("post", post())
            set("put", put())
            set("delete", delete())
        }
        env["okhttp"] = okhttp
        if (!env["package"].isnil()) env["package"]["loaded"]["okhttp"] = okhttp
        return NIL
    }

    inner class get : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.arg(2).takeIf { !it.isnil() }?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.tojstring(), table.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg1().checkjstring()
                    ).build()
                ).execute()
            )
        }
    }

    inner class post : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.arg(2).checktable().apply {
                for (key in keys()) {
                    builder.add(key.tojstring(), get(key).tojstring())
                }
            }
            args.arg(3).takeIf { !it.isnil() }?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.tojstring(), table.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg1().checkjstring()
                    ).post(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }

    inner class delete : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.arg(2).checktable().apply {
                for (key in keys()) {
                    builder.add(key.tojstring(), get(key).tojstring())
                }
            }
            args.arg(3).takeIf { !it.isnil() }?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.tojstring(), table.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg1().checkjstring()
                    ).delete(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }

    inner class put : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.arg(2).checktable().apply {
                for (key in keys()) {
                    builder.add(key.tojstring(), get(key).tojstring())
                }
            }
            args.arg(3).takeIf { !it.isnil() }?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.tojstring(), table.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg1().checkjstring()
                    ).put(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }
}
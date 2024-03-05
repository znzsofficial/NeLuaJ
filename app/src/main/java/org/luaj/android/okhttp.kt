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
        val okhttp = LuaTable()
        okhttp.set("get", get())
        okhttp.set("post", post())
        okhttp.set("put", put())
        okhttp.set("delete", delete())
        env["okhttp"] = okhttp
        if (!env["package"].isnil()) env["package"]["loaded"]["okhttp"] = okhttp
        return NIL
    }

    inner class get : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            var headersTable = args.arg(2)
            val requestBuilder = Request.Builder()
            if (!headersTable.isnil()) {
                headersTable = headersTable.checktable()
                for (key in headersTable.keys()) {
                    requestBuilder.addHeader(key.tojstring(), headersTable.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg(1).checkjstring()
                    ).build()
                ).execute()
            )
        }
    }

    inner class post : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val bodyTable = args.arg(2).checktable()
            var headersTable = args.arg(3).checktable()
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            for (key in bodyTable.keys()) {
                builder.add(key.tojstring(), bodyTable.get(key).tojstring())
            }
            if (!headersTable.isnil()) {
                headersTable = headersTable.checktable()
                for (key in headersTable.keys()) {
                    requestBuilder.addHeader(key.tojstring(), headersTable.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg(1).checkjstring()
                    ).post(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }

    inner class delete : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val bodyTable = args.arg(2).checktable()
            var headersTable = args.arg(3).checktable()
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            for (key in bodyTable.keys()) {
                builder.add(key.tojstring(), bodyTable.get(key).tojstring())
            }
            if (!headersTable.isnil()) {
                headersTable = headersTable.checktable()
                for (key in headersTable.keys()) {
                    requestBuilder.addHeader(key.tojstring(), headersTable.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg(1).checkjstring()
                    ).delete(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }

    inner class put : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val bodyTable = args.arg(2).checktable()
            var headersTable = args.arg(3).checktable()
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            for (key in bodyTable.keys()) {
                builder.add(key.tojstring(), bodyTable.get(key).tojstring())
            }
            if (!headersTable.isnil()) {
                headersTable = headersTable.checktable()
                for (key in headersTable.keys()) {
                    requestBuilder.addHeader(key.tojstring(), headersTable.get(key).tojstring())
                }
            }
            return CoerceJavaToLua.coerce(
                client.newCall(
                    requestBuilder.url(
                        args.arg(1).checkjstring()
                    ).put(
                        builder.build()
                    ).build()
                ).execute()
            )
        }
    }
}
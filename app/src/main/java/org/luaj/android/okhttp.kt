package org.luaj.android

import github.znzsofficial.argAt
import github.znzsofficial.asString
import github.znzsofficial.firstArg
import github.znzsofficial.ifNotNil
import github.znzsofficial.isNotNil
import github.znzsofficial.secondArg
import github.znzsofficial.toLuaValue
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.luaj.Globals
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.VarArgFunction


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
        if (env["package"].isNotNil()) env["package"]["loaded"]["okhttp"] = okhttp
        return NIL
    }

    inner class get : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.secondArg().ifNotNil()?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.asString(), table.get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).build()
            ).execute().toLuaValue()
        }
    }

    inner class post : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.asString(), table.get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).post(
                    builder.build()
                ).build()
            ).execute().toLuaValue()
        }
    }

    inner class delete : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.asString(), table.get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).delete(
                    builder.build()
                ).build()
            ).execute().toLuaValue()
        }
    }

    inner class put : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.let {
                val table = it.checktable()
                for (key in table.keys()) {
                    requestBuilder.addHeader(key.asString(), table.get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).put(
                    builder.build()
                ).build()
            ).execute().toLuaValue()
        }
    }
}
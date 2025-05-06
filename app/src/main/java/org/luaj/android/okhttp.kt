package org.luaj.android

import android.annotation.SuppressLint
import com.androlua.LuaActivity
import com.nekolaska.ktx.argAt
import com.nekolaska.ktx.asString
import com.nekolaska.ktx.firstArg
import com.nekolaska.ktx.ifNotNil
import com.nekolaska.ktx.isNotNil
import com.nekolaska.ktx.secondArg
import com.nekolaska.ktx.toLuaInstance
import com.nekolaska.ktx.toLuaValue
import okhttp3.Call
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.luaj.Globals
import org.luaj.LuaFunction
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.VarArgFunction
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

private fun OkHttpClient.Builder.setTimeout(timeout: Long) =
    callTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .connectTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(timeout, java.util.concurrent.TimeUnit.SECONDS)

class AsyncOkHttp(
    private val context: LuaActivity,
    private val client: OkHttpClient = OkHttpClient.Builder().setTimeout(30).build()
) {
    val unsafe by lazy {
        val trustAllCerts = arrayOf<TrustManager>(
            @SuppressLint("CustomX509TrustManager")
            object : X509TrustManager {
                @SuppressLint("TrustAllX509TrustManager")
                override fun checkClientTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) {
                }

                @SuppressLint("TrustAllX509TrustManager")
                override fun checkServerTrusted(
                    chain: Array<out java.security.cert.X509Certificate>?,
                    authType: String?
                ) {
                }

                override fun getAcceptedIssuers(): Array<out java.security.cert.X509Certificate> =
                    arrayOf()
            })

        AsyncOkHttp(
            context,
            OkHttpClient.Builder().apply {
                setTimeout(30)
                sslSocketFactory(SSLContext.getInstance("SSL").apply {
                    init(null, trustAllCerts, java.security.SecureRandom())
                }.socketFactory, trustAllCerts[0] as X509TrustManager)
                hostnameVerifier { hostname, session -> true } // 忽略主机名验证
            }.build()
        )
    }

    @JvmOverloads
    fun get(
        url: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        client.newCall(
            if (headers != null) {
                url.urlBuilder().headers(
                    okhttp3.Headers.Builder().apply {
                        for (i in headers.keys) add(i, headers[i] ?: "null")
                    }.build()
                ).build()
            } else {
                url.urlBuilder().build()
            }
        ).enqueueWithCallback(callback)

    @JvmOverloads
    fun postText(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        post(
            url,
            body.toRequestBody("text/plain; charset=utf-8".toMediaTypeOrNull()),
            headers,
            callback
        )

    @JvmOverloads
    fun postJson(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) =
        post(
            url,
            body.toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()),
            headers,
            callback
        )

    private fun parseBody(body: String) =
        FormBody.Builder().apply {
            for (i in body.split("&")) {
                val split = i.split("=")
                add(split[0], split[1])
            }
        }.build()

    @JvmOverloads
    fun post(
        url: String,
        body: String,
        headers: Map<String, String>? = null,
        callback: LuaFunction
    ) = post(url, parseBody(body), headers, callback)

    fun post(
        url: String,
        body: RequestBody,
        headers: Map<String, String>?,
        callback: LuaFunction
    ) =
        client.newCall(
            if (headers != null) {
                url.urlBuilder()
                    .post(body)
                    .headers(
                        okhttp3.Headers.Builder().apply {
                            for (i in headers.keys) add(i, headers[i] ?: "null")
                        }.build()
                    ).build()
            } else
                url.urlBuilder().post(body).build()
        ).enqueueWithCallback(callback)

    private fun Call.enqueueWithCallback(callback: LuaFunction) =
        enqueue(object : okhttp3.Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                context.runOnUiThread {
                    try {
                        callback.call(e.message)
                    } catch (e: Exception) {
                        context.sendMsg("网络请求失败，回调发生异常：${e.message}")
                    }
                }
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    val body = response.body?.string()
                    val code = response.code
                    context.runOnUiThread {
                        runCatching {
                            callback.call(
                                code.toLuaValue(),
                                body.toLuaValue(),
                                response.toLuaInstance()
                            )
                        }.onFailure { context.sendMsg("回调发生异常：${it.message}") }
                    }
                } catch (e: Exception) {
                    context.sendMsg("网络请求发生异常：${e.message}")
                }
            }
        })

    private fun String.urlBuilder() = Request.Builder().url(this)
}

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
            set("head", head())
            set("patch", patch())
        }
        env["okhttp"] = okhttp
        if (env["package"].isNotNil()) env["package"]["loaded"]["okhttp"] = okhttp
        return NIL
    }

    inner class get : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.secondArg().ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).build()
            ).execute().toLuaInstance()
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
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).post(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
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
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).delete(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
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
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).put(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }

    inner class head : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val requestBuilder = Request.Builder()
            args.secondArg().ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).head().build()
            ).execute().toLuaInstance()
        }
    }

    inner class patch : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val builder = FormBody.Builder()
            val requestBuilder = Request.Builder()
            args.secondArg().checktable().apply {
                for (key in keys()) {
                    builder.add(key.asString(), get(key).asString())
                }
            }
            args.argAt(3).ifNotNil()?.checktable()?.apply {
                for (key in keys()) {
                    requestBuilder.addHeader(key.asString(), get(key).asString())
                }
            }
            return client.newCall(
                requestBuilder.url(
                    args.firstArg().checkjstring()
                ).patch(
                    builder.build()
                ).build()
            ).execute().toLuaInstance()
        }
    }
}
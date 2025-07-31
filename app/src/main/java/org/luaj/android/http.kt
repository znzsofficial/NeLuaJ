package org.luaj.android

import android.annotation.SuppressLint
import android.webkit.MimeTypeMap
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.UnsupportedEncodingException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.Charset
import java.security.KeyManagementException
import java.security.NoSuchAlgorithmException
import java.security.cert.X509Certificate
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object http {
    private const val BOUNDARY = "----qwertyuiopasdfghjklzxcvbnm"

    var header: HashMap<String, String>? = null

    init {
        try {
            val sslcontext = SSLContext.getInstance("SSL")
            sslcontext.init(
                null, arrayOf<TrustManager>(
                    @SuppressLint("CustomX509TrustManager")
                    object : X509TrustManager {
                        @SuppressLint("TrustAllX509TrustManager")
                        override fun checkClientTrusted(
                            chain: Array<X509Certificate>,
                            authType: String
                        ) {
                        }

                        @SuppressLint("TrustAllX509TrustManager")
                        override fun checkServerTrusted(
                            chain: Array<X509Certificate>,
                            authType: String
                        ) {
                        }

                        override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
                    }), java.security.SecureRandom()
            )
            val ignoreHostnameVerifier = HostnameVerifier { _, _ -> true }
            HttpsURLConnection.setDefaultHostnameVerifier(ignoreHostnameVerifier)
            HttpsURLConnection.setDefaultSSLSocketFactory(sslcontext.socketFactory)
        } catch (e: Exception) {
            when (e) {
                is NoSuchAlgorithmException, is KeyManagementException -> e.printStackTrace()
                else -> throw e
            }
        }
    }

    // --- GET 方法 ---


    @JvmOverloads
    fun get(url: String, header: HashMap<String, String>? = null): HttpResult {
        val task = LuaHttp(url, "GET", null, null, header)
        return task.connection()
    }


    @JvmOverloads
    fun get(
        url: String,
        cookie: String,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val (actualCookie, actualCharset) = if (charset == null && cookie.matches("[\\w\\-]+".toRegex()) && Charset.isSupported(
                cookie
            )
        ) {
            null to cookie
        } else {
            cookie to charset
        }
        val task = LuaHttp(url, "GET", actualCookie, actualCharset, header)
        return task.connection()
    }

    // --- DOWNLOAD 方法 ---
    @JvmOverloads
    fun download(url: String, data: String, header: HashMap<String, String>? = null): HttpResult {
        val task = LuaHttp(url, "GET", null, null, header)
        return task.connection(data)
    }


    @JvmOverloads
    fun download(
        url: String,
        data: String,
        cookie: String,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val task = LuaHttp(url, "GET", cookie, null, header)
        return task.connection(data)
    }

    // --- DELETE 方法 ---
    @JvmOverloads
    fun delete(url: String, header: HashMap<String, String>? = null): HttpResult {
        val task = LuaHttp(url, "DELETE", null, null, header)
        return task.connection()
    }


    @JvmOverloads
    fun delete(
        url: String,
        cookie: String,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val (actualCookie, actualCharset) = if (charset == null && cookie.matches("[\\w\\-]+".toRegex()) && Charset.isSupported(
                cookie
            )
        ) {
            null to cookie
        } else {
            cookie to charset
        }
        val task = LuaHttp(url, "DELETE", actualCookie, actualCharset, header)
        return task.connection()
    }

    // --- PUT 方法 ---
    @JvmOverloads
    fun put(url: String, data: String, header: HashMap<String, String>? = null): HttpResult {
        val task = LuaHttp(url, "PUT", null, null, header)
        return task.connection(data)
    }


    @JvmOverloads
    fun put(
        url: String,
        data: String,
        cookie: String,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val (actualCookie, actualCharset) = if (charset == null && cookie.matches("[\\w\\-]+".toRegex()) && Charset.isSupported(
                cookie
            )
        ) {
            null to cookie
        } else {
            cookie to charset
        }
        val task = LuaHttp(url, "PUT", actualCookie, actualCharset, header)
        return task.connection(data)
    }

    // --- POST 方法 ---

    // 组A: post(url, data: String, ...)
    @JvmOverloads
    fun post(url: String, data: String, header: HashMap<String, String>? = null): HttpResult {
        val task = LuaHttp(url, "POST", null, null, header)
        return task.connection(data)
    }


    @JvmOverloads
    fun post(
        url: String,
        data: String,
        cookie: String,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val (actualCookie, actualCharset) = if (charset == null && cookie.matches("[\\w\\-]+".toRegex()) && Charset.isSupported(
                cookie
            )
        ) {
            null to cookie
        } else {
            cookie to charset
        }
        val task = LuaHttp(url, "POST", actualCookie, actualCharset, header)
        return task.connection(data)
    }

    // 组B: post(url, data: HashMap, ...) - 委托给组A
    @JvmOverloads
    fun post(
        url: String,
        data: HashMap<String, String>,
        cookie: String? = null,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val stringData = formatMap(data)
        return if (cookie != null) {
            post(url, stringData, cookie, charset, header)
        } else {
            post(url, stringData, header)
        }
    }

    // 组C: post(url, data: HashMap, file: HashMap, ...) - Multipart
    @JvmOverloads
    fun post(
        url: String,
        data: HashMap<String, String>,
        file: HashMap<String, String>,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val finalHeader = header ?: HashMap()
        finalHeader["Content-Type"] = "multipart/form-data;boundary=$BOUNDARY"
        val task = LuaHttp(url, "POST", null, null, finalHeader)
        return task.connection(formatMultiDate(data, file, null))
    }


    @JvmOverloads
    fun post(
        url: String,
        data: HashMap<String, String>,
        file: HashMap<String, String>,
        cookie: String,
        charset: String? = null,
        header: HashMap<String, String>? = null
    ): HttpResult {
        val finalHeader = header ?: HashMap()
        finalHeader["Content-Type"] = "multipart/form-data;boundary=$BOUNDARY"

        val (actualCookie, actualCharset) = if (charset == null && cookie.matches("[\\w\\-.:]+".toRegex()) && Charset.isSupported(
                cookie
            )
        ) {
            null to cookie
        } else {
            cookie to charset
        }
        val task = LuaHttp(url, "POST", actualCookie, actualCharset, finalHeader)
        return task.connection(formatMultiDate(data, file, actualCharset))
    }

    // --- 私有辅助方法 ---
    private fun formatMap(data: Map<String, String>): String {
        return data.map { (key, value) -> "$key=$value" }.joinToString("&")
    }

    private fun getType(file: String): String {
        val extension = File(file).extension
        return if (extension.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        } else {
            "application/octet-stream"
        }
    }

    private fun formatMultiDate(
        data: HashMap<String, String>,
        file: HashMap<String, String>,
        charset: String?
    ): ByteArray {
        val finalCharset = charset ?: "UTF-8"
        val buff = ByteArrayOutputStream()
        try {
            // 写入表单数据
            data.forEach { (key, value) ->
                val part = "--$BOUNDARY\r\n" +
                        "Content-Disposition: form-data; name=\"$key\"\r\n\r\n" +
                        "$value\r\n"
                buff.write(part.toByteArray(Charset.forName(finalCharset)))
            }
            // 写入文件数据
            file.forEach { (key, value) ->
                val filePartHeader = "--$BOUNDARY\r\n" +
                        "Content-Disposition: form-data; name=\"$key\"; filename=\"${File(value).name}\"\r\n" +
                        "Content-Type: ${getType(value)}\r\n\r\n"
                buff.write(filePartHeader.toByteArray(Charset.forName(finalCharset)))
                // 安全地读取文件并写入
                buff.write(FileInputStream(value).use { it.readBytes() })
                buff.write("\r\n".toByteArray(Charset.forName(finalCharset)))
            }
            // 写入结束标记
            buff.write("--$BOUNDARY--\r\n".toByteArray(Charset.forName(finalCharset)))
        } catch (e: IOException) {
            e.printStackTrace()
        }
        return buff.toByteArray()
    }

    // --- 内部类与接口 ---

    class LuaHttp(
        private val mUrl: String,
        private val mMethod: String,
        private val mCookie: String?,
        private var mCharset: String?,
        private val mHeader: HashMap<String, String>?
    ) {
        private var mData: ByteArray? = null

        fun connection(vararg p1: Any): HttpResult {
            try {
                val url = URL(mUrl)
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 6000
                HttpURLConnection.setFollowRedirects(true)
                conn.doInput = true
                conn.setRequestProperty("Accept-Language", "zh-cn,zh;q=0.5")

                val finalCharset = mCharset ?: "UTF-8".also { mCharset = it }
                conn.setRequestProperty("Accept-Charset", finalCharset)

                mCookie?.let { conn.setRequestProperty("Cookie", it) }

                // 应用全局和单次请求的 Header
                header?.forEach { (k, v) -> conn.setRequestProperty(k, v) }
                mHeader?.forEach { (k, v) -> conn.setRequestProperty(k, v) }

                conn.requestMethod = mMethod

                // 处理请求体
                if (mMethod != "GET" && p1.isNotEmpty()) {
                    mData = formatData(p1)
                    conn.doOutput = true
                    mData?.let { conn.setRequestProperty("Content-length", it.size.toString()) }
                }

                conn.connect()

                // 处理下载
                if (mMethod == "GET" && p1.isNotEmpty()) {
                    val filePath = p1[0] as String
                    val f = File(filePath)
                    f.parentFile?.mkdirs()
                    f.outputStream().use { os -> conn.inputStream.use { it.copyTo(os) } }
                    return HttpResult(conn.responseCode, f.absolutePath, null, conn.headerFields)
                }

                // 发送请求体
                if (p1.isNotEmpty()) {
                    mData?.let { conn.outputStream.use { os -> os.write(it) } }
                }

                val code = conn.responseCode
                val hs = conn.headerFields

                // 提取 Cookie
                val cok = hs["Set-Cookie"]?.joinToString(";") ?: ""

                // 从响应头中更新字符集
                hs["Content-Type"]?.firstOrNull()?.let { s ->
                    s.split(';').forEach { part ->
                        if (part.trim().startsWith("charset", ignoreCase = true)) {
                            mCharset = part.split('=')[1].trim()
                            return@let
                        }
                    }
                }

                val responseCharset = mCharset ?: "UTF-8"
                val buf = StringBuilder()
                readStreamInto(conn.inputStream, buf, responseCharset)
                readStreamInto(conn.errorStream, buf, responseCharset)

                return HttpResult(code, buf.toString(), cok, hs)
            } catch (e: Exception) {
                e.printStackTrace()
                return HttpResult(-1, e.message, null, null)
            }
        }

        private fun readStreamInto(
            stream: java.io.InputStream?,
            builder: StringBuilder,
            charset: String
        ) {
            stream?.use {
                it.bufferedReader(Charset.forName(charset)).forEachLine { line ->
                    if (builder.isNotEmpty()) builder.append('\n')
                    builder.append(line)
                }
            }
        }

        @Throws(UnsupportedEncodingException::class, IOException::class)
        private fun formatData(p1: Array<out Any>): ByteArray? = if (p1.isNotEmpty()) {
            when (val obj = p1[0]) {
                is String -> obj.toByteArray(charset(mCharset!!))
                is ByteArray -> obj
                is File -> obj.readBytes()
                is Map<*, *> -> @Suppress("UNCHECKED_CAST") formatData(obj as Map<String, String>)
                else -> null
            }
        } else {
            null
        }

        @Throws(UnsupportedEncodingException::class)
        private fun formatData(obj: Map<String, String>): ByteArray {
            return obj.map { (key, value) -> "$key=$value" }
                .joinToString("&").toByteArray(charset(mCharset!!))
        }
    }

    data class HttpResult(
        @JvmField val code: Int,
        @JvmField val text: String?,
        @JvmField val cookie: String?,
        @JvmField val header: Map<String, List<String>>?
    )
}
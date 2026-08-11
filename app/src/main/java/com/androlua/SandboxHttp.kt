package com.androlua

import okhttp3.Dns
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.VarArgFunction
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.net.IDN
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.Proxy
import java.net.UnknownHostException
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okio.BufferedSink

/** Restricted HTTPS client for AI-generated Lua. It never exposes OkHttp or Java objects. */
internal object SandboxHttp {
    private const val MAX_ALLOWED_HOSTS = 8
    private const val MAX_REQUESTS = 4
    private const val MAX_REQUEST_BODY_BYTES = 256 * 1024
    private const val MAX_RESPONSE_BODY_BYTES = 512 * 1024
    private const val MAX_HEADERS = 24
    private const val MAX_HEADER_BYTES = 16 * 1024
    private const val MAX_RESPONSE_HEADERS = 64
    private const val MAX_RESPONSE_HEADER_BYTES = 32 * 1024
    private const val DEFAULT_TIMEOUT_MS = 4_000L
    private const val MIN_TIMEOUT_MS = 1_000L
    private const val MAX_TIMEOUT_MS = 6_000L
    private val allowedMethods = setOf("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE")
    private val blockedHeaders = setOf(
        "connection", "content-length", "host", "keep-alive", "proxy-authenticate",
        "proxy-authorization", "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade"
    )

    fun install(globals: Globals, allowedHosts: Set<String>): Closeable {
        if (allowedHosts.isEmpty()) {
            globals.set("http", LuaTable().apply {
                set("request", object : VarArgFunction() {
                    override fun invoke(args: Varargs): Varargs {
                        throw LuaError("sandbox HTTP host was not authorized")
                    }
                })
            })
            return Closeable { }
        }
        val policy = NetworkPolicy(allowedHosts)
        val client = lazy(LazyThreadSafetyMode.NONE) { createClient(policy) }
        val requestCount = AtomicInteger()
        globals.set("http", LuaTable().apply {
            set("request", object : VarArgFunction() {
                override fun invoke(args: Varargs): Varargs {
                    if (requestCount.incrementAndGet() > MAX_REQUESTS) {
                        throw LuaError("sandbox HTTP is limited to $MAX_REQUESTS requests per run")
                    }
                    return execute(policy, args.arg(1), args.arg(2)) { client.value }
                }
            })
        })
        return Closeable {
            if (client.isInitialized()) {
                client.value.dispatcher.cancelAll()
                client.value.connectionPool.evictAll()
                client.value.dispatcher.executorService.shutdown()
            }
        }
    }

    private fun createClient(policy: NetworkPolicy): OkHttpClient = OkHttpClient.Builder()
        .proxy(Proxy.NO_PROXY)
        .dns(policy)
        .retryOnConnectionFailure(false)
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .writeTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .callTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .build()

    fun parseAllowedHosts(raw: String?): Set<String> {
        if (raw.isNullOrBlank()) return emptySet()
        if (raw.length > 2_048) throw LuaError("sandbox HTTP host list is too large")
        val hosts = LinkedHashSet<String>()
        raw.lineSequence().forEach { line ->
            val value = line.trim()
            if (value.isNotEmpty()) hosts += canonicalHost(value)
        }
        if (hosts.size > MAX_ALLOWED_HOSTS) {
            throw LuaError("sandbox HTTP allows at most $MAX_ALLOWED_HOSTS hosts per run")
        }
        return hosts
    }

    private fun execute(
        policy: NetworkPolicy,
        urlArg: LuaValue,
        optionsArg: LuaValue,
        client: () -> OkHttpClient
    ): LuaValue {
        val url = policy.validateUrl(urlArg.checkjstring())
        val options = if (optionsArg.isnil()) null else optionsArg.checktable()
        val method = options?.get("method")?.optjstring("GET")
            ?.uppercase(Locale.US) ?: "GET"
        if (method !in allowedMethods) throw LuaError("sandbox HTTP method is not allowed: $method")

        val headers = readHeaders(options?.get("headers") ?: LuaValue.NIL)
        val bodyValue = options?.get("body") ?: LuaValue.NIL
        val body = if (bodyValue.isnil()) null else luaBytes(bodyValue, MAX_REQUEST_BODY_BYTES, "request body")
        if ((method == "GET" || method == "HEAD") && body != null) {
            throw LuaError("$method requests cannot include a body")
        }
        val contentType = headers.entries.firstOrNull { it.key.equals("content-type", true) }?.value
            ?: options?.get("content_type")?.optjstring(null)
            ?: "text/plain; charset=utf-8"
        val requestBody = when {
            method == "GET" || method == "HEAD" -> null
            body != null -> oneShotBody(body, contentType)
            else -> oneShotBody(ByteArray(0), contentType)
        }
        val request = Request.Builder().url(url).method(method, requestBody).apply {
            headers.forEach { (name, value) -> addHeader(name, value) }
        }.build()
        val timeout = options?.get("timeout")?.optlong(DEFAULT_TIMEOUT_MS)
            ?.coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS) ?: DEFAULT_TIMEOUT_MS
        val callClient = client().newBuilder().callTimeout(timeout, TimeUnit.MILLISECONDS).build()

        try {
            callClient.newCall(request).execute().use { response ->
                val responseBody = response.body.byteStream().use(::readBounded)
                return LuaTable().apply {
                    set("ok", LuaValue.valueOf(response.isSuccessful))
                    set("status", LuaValue.valueOf(response.code))
                    set("message", LuaValue.valueOf(response.message))
                    set("url", LuaValue.valueOf(response.request.url.toString()))
                    set("body", LuaString.valueOf(responseBody))
                    set("headers", readResponseHeaders(response.headers))
                    set("header_values", readResponseHeaderValues(response.headers))
                }
            }
        } catch (error: LuaError) {
            throw error
        } catch (error: Exception) {
            throw LuaError("sandbox HTTP request failed: ${error.message ?: error.javaClass.simpleName}")
        }
    }

    private fun readHeaders(value: LuaValue): Map<String, String> {
        if (value.isnil()) return emptyMap()
        val table = value.checktable()
        if (table.size() > MAX_HEADERS) throw LuaError("sandbox HTTP allows at most $MAX_HEADERS headers")
        val headers = LinkedHashMap<String, String>()
        var totalBytes = 0
        var entry = table.next(LuaValue.NIL)
        while (!entry.arg1().isnil()) {
            val name = entry.arg1().checkjstring().trim()
            val headerValue = entry.arg(2).checkjstring()
            val lowerName = name.lowercase(Locale.US)
            if (name.isEmpty() || lowerName in blockedHeaders) {
                throw LuaError("sandbox HTTP header is not allowed: $name")
            }
            totalBytes += name.toByteArray(StandardCharsets.UTF_8).size
            totalBytes += headerValue.toByteArray(StandardCharsets.UTF_8).size
            if (totalBytes > MAX_HEADER_BYTES) throw LuaError("sandbox HTTP headers exceed 16 KiB")
            headers[name] = headerValue
            entry = table.next(entry.arg1())
        }
        return headers
    }

    private fun readResponseHeaders(headers: Headers): LuaTable {
        val names = headers.names().sorted()
        if (names.size > MAX_RESPONSE_HEADERS) {
            throw LuaError("sandbox HTTP response has too many headers")
        }
        var totalBytes = 0
        return LuaTable().apply {
            names.forEach { name ->
                val value = headers.values(name).joinToString(", ")
                totalBytes += name.toByteArray(StandardCharsets.UTF_8).size
                totalBytes += value.toByteArray(StandardCharsets.UTF_8).size
                if (totalBytes > MAX_RESPONSE_HEADER_BYTES) {
                    throw LuaError("sandbox HTTP response headers exceed 32 KiB")
                }
                set(name.lowercase(Locale.US), value)
            }
        }
    }

    private fun readResponseHeaderValues(headers: Headers): LuaTable = LuaTable().apply {
        headers.names().sorted().forEach { name ->
            set(name.lowercase(Locale.US), LuaTable().apply {
                headers.values(name).forEachIndexed { index, value -> set(index + 1, value) }
            })
        }
    }

    private fun luaBytes(value: LuaValue, limit: Int, label: String): ByteArray {
        val string = value.checkstring()
        if (string.length() > limit) throw LuaError("sandbox HTTP $label exceeds ${limit / 1024} KiB")
        return ByteArray(string.length()).also { string.copyInto(0, it, 0, it.size) }
    }

    private fun oneShotBody(bytes: ByteArray, contentType: String): RequestBody = object : RequestBody() {
        override fun contentType() = contentType.toMediaTypeOrNull()
        override fun contentLength(): Long = bytes.size.toLong()
        override fun writeTo(sink: BufferedSink) {
            sink.write(bytes)
        }
        override fun isOneShot(): Boolean = true
    }

    private fun readBounded(stream: java.io.InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_RESPONSE_BODY_BYTES) {
                throw LuaError("sandbox HTTP response body exceeds ${MAX_RESPONSE_BODY_BYTES / 1024} KiB")
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    internal fun canonicalHost(raw: String): String {
        val value = raw.trim().trimEnd('.')
        if (value.isEmpty() || value.contains('/') || value.contains(':') || value.contains('@')) {
            throw LuaError("invalid sandbox HTTP host: $raw")
        }
        val host = try {
            IDN.toASCII(value, IDN.USE_STD3_ASCII_RULES).lowercase(Locale.US)
        } catch (_: IllegalArgumentException) {
            throw LuaError("invalid sandbox HTTP host: $raw")
        }
        if (host.length > 253 || host.split('.').any { it.isEmpty() || it.length > 63 }) {
            throw LuaError("invalid sandbox HTTP host: $raw")
        }
        if (isIpLiteral(host) || isReservedHostName(host)) {
            throw LuaError("sandbox HTTP host is not public: $raw")
        }
        if (!host.contains('.')) throw LuaError("invalid sandbox HTTP host: $raw")
        return host
    }

    private fun isIpLiteral(host: String): Boolean = host.all { it.isDigit() || it == '.' }

    private fun isReservedHostName(host: String): Boolean = host == "localhost" ||
        host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".internal") ||
        host.endsWith(".localdomain") || host.endsWith(".home.arpa") || host.endsWith(".test") || host.endsWith(".invalid") ||
        host.endsWith(".example") || host.endsWith(".onion")

    internal fun isPublicAddress(address: InetAddress): Boolean {
        if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress ||
            address.isSiteLocalAddress || address.isMulticastAddress) return false
        val bytes = address.address.map { it.toInt() and 0xff }
        return when (address) {
            is Inet4Address -> when {
                bytes[0] == 0 || bytes[0] == 10 || bytes[0] == 127 -> false
                bytes[0] == 100 && bytes[1] in 64..127 -> false
                bytes[0] == 169 && bytes[1] == 254 -> false
                bytes[0] == 172 && bytes[1] in 16..31 -> false
                bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 0 -> false
                bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 2 -> false
                bytes[0] == 192 && bytes[1] == 31 && bytes[2] == 196 -> false
                bytes[0] == 192 && bytes[1] == 168 -> false
                bytes[0] == 192 && bytes[1] == 88 && bytes[2] == 99 -> false
                bytes[0] == 198 && bytes[1] in 18..19 -> false
                bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100 -> false
                bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113 -> false
                bytes[0] >= 224 -> false
                else -> true
            }
            is Inet6Address -> {
                val nat64Prefix = bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b
                    && bytes.slice(4..11).all { it == 0 }
                if (nat64Prefix) {
                    return isPublicAddress(InetAddress.getByAddress(byteArrayOf(
                        bytes[12].toByte(), bytes[13].toByte(), bytes[14].toByte(), bytes[15].toByte()
                    )))
                }
                val globalUnicast = bytes[0] and 0xe0 == 0x20
                val ietfAssignments = bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] and 0xfe == 0
                val globallyReachableIetfAssignment = if (!ietfAssignments) true else {
                    val secondGroup = bytes[2] shl 8 or bytes[3]
                    val thirdGroup = bytes[4] shl 8 or bytes[5]
                    when {
                        secondGroup == 0x0001 -> bytes.slice(4..13).all { it == 0 } &&
                            bytes[14] == 0 && bytes[15] in 1..3
                        secondGroup == 0x0003 -> true
                        secondGroup == 0x0004 && thirdGroup == 0x0112 -> true
                        secondGroup in 0x0020..0x002f -> true
                        secondGroup in 0x0030..0x003f -> true
                        else -> false
                    }
                }
                val documentation = bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8
                val sixToFour = bytes[0] == 0x20 && bytes[1] == 0x02
                val documentationV2 = bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] and 0xf0 == 0
                globalUnicast && globallyReachableIetfAssignment && !documentation && !sixToFour && !documentationV2
            }
            else -> false
        }
    }

    internal fun validatePublicUrl(raw: String): HttpUrl {
        val url = raw.toHttpUrlOrNull() ?: throw IllegalArgumentException("invalid HTTPS URL")
        if (url.scheme != "https") throw IllegalArgumentException("only HTTPS URLs are allowed")
        if (url.username.isNotEmpty() || url.password.isNotEmpty()) {
            throw IllegalArgumentException("URLs cannot contain credentials")
        }
        if (url.port != 443) throw IllegalArgumentException("only HTTPS port 443 is allowed")
        try {
            canonicalHost(url.host)
        } catch (error: LuaError) {
            throw IllegalArgumentException(error.message?.removePrefix("sandbox HTTP ") ?: "invalid HTTPS host")
        }
        return url
    }

    internal class PublicDns(private val allowedHosts: Set<String>) : Dns {
        override fun lookup(hostname: String): List<InetAddress> {
            val host = try {
                canonicalHost(hostname)
            } catch (error: LuaError) {
                throw UnknownHostException(error.message ?: "invalid HTTPS host")
            }
            if (host !in allowedHosts) throw UnknownHostException("HTTPS host was not authorized: $host")
            val addresses = Dns.SYSTEM.lookup(host)
            if (addresses.isEmpty() || addresses.any { !isPublicAddress(it) }) {
                throw UnknownHostException("HTTPS host did not resolve exclusively to public addresses: $host")
            }
            return addresses
        }
    }

    private class NetworkPolicy(private val allowedHosts: Set<String>) : Dns {
        fun validateUrl(raw: String): HttpUrl {
            val url = try {
                validatePublicUrl(raw)
            } catch (error: IllegalArgumentException) {
                val message = when (error.message) {
                    "invalid HTTPS URL" -> "invalid sandbox HTTP URL"
                    "only HTTPS URLs are allowed" -> "sandbox HTTP only allows HTTPS"
                    "URLs cannot contain credentials" -> "sandbox HTTP URLs cannot contain credentials"
                    "only HTTPS port 443 is allowed" -> "sandbox HTTP only allows HTTPS port 443"
                    else -> "sandbox HTTP ${error.message ?: "URL is invalid"}"
                }
                throw LuaError(message)
            }
            val host = canonicalHost(url.host)
            if (host !in allowedHosts) {
                throw LuaError("sandbox HTTP host was not authorized: $host")
            }
            return url
        }

        override fun lookup(hostname: String): List<InetAddress> {
            return try {
                PublicDns(allowedHosts).lookup(hostname)
            } catch (error: UnknownHostException) {
                throw UnknownHostException(error.message?.replace("HTTPS host", "sandbox HTTP host"))
            }
        }
    }
}

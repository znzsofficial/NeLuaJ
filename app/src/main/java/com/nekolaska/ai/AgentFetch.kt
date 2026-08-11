package com.nekolaska.ai

import com.androlua.SandboxHttp
import okhttp3.Call
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.net.Proxy
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Read-only public HTTPS transport exposed to the coding Agent as a confirmed tool. */
object AgentFetch {
    private const val DEFAULT_TIMEOUT_MS = 8_000L
    private const val MIN_TIMEOUT_MS = 1_000L
    private const val MAX_TIMEOUT_MS = 15_000L
    private const val DEFAULT_MAX_CHARS = 12_000
    private const val MIN_MAX_CHARS = 256
    private const val MAX_MAX_CHARS = 50_000
    private const val MAX_REDIRECTS = 3
    private const val MAX_URL_LENGTH = 8_192
    private val redirectCodes = setOf(301, 302, 303, 307, 308)
    private val currentCall = AtomicReference<Call?>()
    private val baseClient = OkHttpClient.Builder()
        .proxy(Proxy.NO_PROXY)
        .cookieJar(CookieJar.NO_COOKIES)
        .retryOnConnectionFailure(false)
        .followRedirects(false)
        .followSslRedirects(false)
        .connectTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .writeTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .callTimeout(MAX_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .build()

    internal data class RequestOptions(
        val url: HttpUrl,
        val method: String,
        val timeoutMs: Long,
        val maxChars: Int
    )

    @JvmStatic
    fun fetch(rawUrl: String, rawMethod: String?, rawTimeoutMs: Long, rawMaxChars: Int): String {
        val options = validateRequest(rawUrl, rawMethod, rawTimeoutMs, rawMaxChars)
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(options.timeoutMs)
        var url = options.url
        var redirects = 0

        while (true) {
            val remainingNanos = deadlineNanos - System.nanoTime()
            if (remainingNanos <= 0) throw IllegalStateException("request timed out")
            val host = SandboxHttp.canonicalHost(url.host)
            val client = baseClient.newBuilder()
                .dns(SandboxHttp.PublicDns(setOf(host)))
                .callTimeout(remainingNanos, TimeUnit.NANOSECONDS)
                .build()
            val request = Request.Builder()
                .url(url)
                .method(options.method, null)
                .header("Accept", "text/html, text/plain, application/json, application/*+json, application/xml, application/*+xml;q=0.9")
                .header("User-Agent", "NeLuaJ-Agent-Fetch/1.0")
                .build()
            val call = client.newCall(request)
            currentCall.set(call)
            var redirectedUrl: HttpUrl? = null
            try {
                call.execute().use { response ->
                    if (response.code in redirectCodes) {
                        val location = response.header("Location")
                            ?: throw IllegalStateException("redirect response omitted Location")
                        if (redirects >= MAX_REDIRECTS) {
                            throw IllegalStateException("redirect limit exceeded ($MAX_REDIRECTS)")
                        }
                        val redirected = response.request.url.resolve(location)
                            ?: throw IllegalStateException("invalid redirect URL")
                        redirectedUrl = SandboxHttp.validatePublicUrl(redirected.toString())
                    } else {
                        return formatResponse(response, options, redirects)
                    }
                }
            } finally {
                currentCall.compareAndSet(call, null)
            }
            url = redirectedUrl ?: throw IllegalStateException("redirect validation failed")
            redirects += 1
        }
    }

    @JvmStatic
    fun cancelPending() {
        currentCall.getAndSet(null)?.cancel()
    }

    internal fun validateRequest(
        rawUrl: String,
        rawMethod: String?,
        rawTimeoutMs: Long,
        rawMaxChars: Int
    ): RequestOptions {
        if (rawUrl.length > MAX_URL_LENGTH) throw IllegalArgumentException("URL is too long")
        val url = SandboxHttp.validatePublicUrl(rawUrl)
        val method = rawMethod.orEmpty().ifBlank { "GET" }.uppercase(Locale.US)
        if (method != "GET" && method != "HEAD") {
            throw IllegalArgumentException("only GET and HEAD are allowed")
        }
        val timeoutMs = (if (rawTimeoutMs > 0) rawTimeoutMs else DEFAULT_TIMEOUT_MS)
            .coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
        val maxChars = (if (rawMaxChars > 0) rawMaxChars else DEFAULT_MAX_CHARS)
            .coerceIn(MIN_MAX_CHARS, MAX_MAX_CHARS)
        return RequestOptions(url, method, timeoutMs, maxChars)
    }

    internal fun isTextual(contentType: MediaType?): Boolean {
        if (contentType == null) return false
        if (contentType.type == "text") return true
        val subtype = contentType.subtype.lowercase(Locale.US)
        return subtype == "json" || subtype.endsWith("+json") ||
            subtype == "xml" || subtype.endsWith("+xml") ||
            subtype == "javascript" || subtype == "x-javascript"
    }

    private fun formatResponse(response: Response, options: RequestOptions, redirects: Int): String {
        val contentType = response.body.contentType()
        val output = StringBuilder()
            .append("URL: ").append(response.request.url).append('\n')
            .append("Status: ").append(response.code).append(' ').append(response.message).append('\n')
            .append("Content-Type: ").append(contentType ?: "unknown").append('\n')
        if (redirects > 0) output.append("Redirects: ").append(redirects).append('\n')
        if (options.method == "HEAD") return output.toString().trimEnd()
        if (!isTextual(contentType)) {
            throw IllegalStateException("response Content-Type is not textual: ${contentType ?: "missing"}")
        }

        val reader = response.body.charStream()
        val body = StringBuilder()
        val buffer = CharArray(4_096)
        var truncated = false
        while (body.length <= options.maxChars) {
            val remaining = options.maxChars + 1 - body.length
            val count = reader.read(buffer, 0, minOf(buffer.size, remaining))
            if (count < 0) break
            body.append(buffer, 0, count)
        }
        if (body.length > options.maxChars) {
            body.setLength(options.maxChars)
            truncated = true
        }
        output.append("\nBody:\n").append(body)
        if (truncated) output.append("\n\n[response truncated at ").append(options.maxChars).append(" characters]")
        return output.toString()
    }
}

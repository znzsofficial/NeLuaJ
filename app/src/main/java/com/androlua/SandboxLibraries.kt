package com.androlua

import org.luaj.Globals
import org.luaj.LuaError
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.OneArgFunction
import org.luaj.lib.VarArgFunction
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64
import java.util.IdentityHashMap

/** Pure computation helpers installed into the untrusted Lua sandbox. */
internal object SandboxLibraries {
    private const val MAX_DEPTH = 64
    private const val MAX_ITEMS = 10_000
    private const val MAX_INSPECT_ITEMS = 1_000
    private const val MAX_INSPECT_STRING_CHARS = 1_024
    private const val MAX_UTILITY_BYTES = 1024 * 1024
    private val jsonNull = object : LuaValue() {
        override fun type(): Int = TUSERDATA
        override fun typename(): String = "json-null"
        override fun tojstring(): String = "json.null"
    }
    private val jsonArrayMetatable = LuaTable().apply {
        set("__metatable", "json array")
    }

    fun install(globals: Globals) {
        globals.set("json", LuaTable().apply {
            set("null", jsonNull)
            set("encode", object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue = valueOf(encodeJson(arg))
            })
            set("decode", object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue = decodeJson(arg.checkjstring())
            })
            set("array", object : OneArgFunction() {
                override fun call(arg: LuaValue): LuaValue {
                    val table = if (arg.isnil()) LuaTable() else arg.checktable()
                    table.setmetatable(jsonArrayMetatable)
                    return table
                }
            })
        })
        globals.set("codec", LuaTable().apply {
            set("base64_encode", byteTransform { LuaValue.valueOf(Base64.getEncoder().encodeToString(it)) })
            set("base64_decode", byteTransform { LuaString.valueOf(Base64.getDecoder().decode(it)) })
            set("hex_encode", byteTransform { bytes ->
                LuaValue.valueOf(bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) })
            })
            set("hex_decode", byteTransform { LuaString.valueOf(decodeHex(it)) })
            set("url_encode", textTransform { URLEncoder.encode(it, StandardCharsets.UTF_8.name()) })
            set("url_decode", textTransform { URLDecoder.decode(it, StandardCharsets.UTF_8.name()) })
        })
        globals.set("hash", LuaTable().apply {
            set("sha256", byteTransform { bytes ->
                LuaValue.valueOf(MessageDigest.getInstance("SHA-256").digest(bytes)
                    .joinToString("") { "%02x".format(it.toInt() and 0xff) })
            })
        })
        globals.set("inspect", object : OneArgFunction() {
            override fun call(arg: LuaValue): LuaValue = valueOf(inspect(arg))
        })
        globals.set("assert_equal", object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs {
                val actual = args.arg(1)
                val expected = args.arg(2)
                if (!deepEquals(actual, expected)) {
                    val prefix = if (args.arg(3).isnil()) "values are not equal" else args.arg(3).tojstring()
                    throw LuaError("$prefix\nexpected: ${inspect(expected)}\nactual: ${inspect(actual)}")
                }
                return actual
            }
        })
    }

    fun inspect(value: LuaValue): String = inspectValue(value, IdentityHashMap(), 0, intArrayOf(0))

    private fun byteTransform(transform: (ByteArray) -> LuaValue): OneArgFunction = object : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue {
            return runCatching { boundUtilityResult(transform(luaBytes(arg))) }
                .getOrElse { throw LuaError(it.message ?: "codec operation failed") }
        }
    }

    private fun luaBytes(value: LuaValue): ByteArray {
        val string = value.checkstring()
        if (string.length() > MAX_UTILITY_BYTES) throw LuaError("utility input exceeds 1 MiB")
        return ByteArray(string.length()).also { string.copyInto(0, it, 0, it.size) }
    }

    private fun textTransform(transform: (String) -> String): OneArgFunction = object : OneArgFunction() {
        override fun call(arg: LuaValue): LuaValue = try {
            val text = arg.checkjstring()
            if (text.toByteArray(StandardCharsets.UTF_8).size > MAX_UTILITY_BYTES) {
                throw LuaError("utility input exceeds 1 MiB")
            }
            boundUtilityResult(valueOf(transform(text)))
        } catch (error: Exception) {
            throw LuaError(error.message ?: "codec operation failed")
        }
    }

    private fun boundUtilityResult(value: LuaValue): LuaValue {
        if (value.isstring() && value.checkstring().length() > MAX_UTILITY_BYTES) {
            throw LuaError("utility result exceeds 1 MiB")
        }
        return value
    }

    private fun decodeHex(bytes: ByteArray): ByteArray {
        val text = bytes.toString(StandardCharsets.UTF_8).trim()
        if (text.length % 2 != 0 || !text.matches(Regex("[0-9a-fA-F]*"))) {
            throw IllegalArgumentException("hex input must contain an even number of hexadecimal digits")
        }
        return ByteArray(text.length / 2) { index ->
            text.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    private fun encodeJson(value: LuaValue): String {
        val out = StringBuilder()
        appendJson(value, out, IdentityHashMap(), 0, intArrayOf(0))
        if (out.toString().toByteArray(StandardCharsets.UTF_8).size > MAX_UTILITY_BYTES) {
            throw LuaError("encoded JSON exceeds 1 MiB")
        }
        return out.toString()
    }

    private fun appendJson(
        value: LuaValue,
        out: StringBuilder,
        active: IdentityHashMap<LuaValue, Boolean>,
        depth: Int,
        itemCount: IntArray
    ) {
        if (depth > MAX_DEPTH) throw LuaError("json value exceeds maximum depth $MAX_DEPTH")
        when {
            value === jsonNull || value.isnil() -> out.append("null")
            value.isboolean() -> out.append(if (value.toboolean()) "true" else "false")
            value.isnumber() -> {
                if (value.isint()) out.append(value.tolong())
                else {
                    val number = value.todouble()
                    if (!number.isFinite()) throw LuaError("json cannot encode non-finite numbers")
                    out.append(number)
                }
            }
            value.isstring() -> appendJsonString(out, value.tojstring())
            value.istable() -> {
                if (active.put(value, true) != null) throw LuaError("json cannot encode cyclic tables")
                try {
                    val table = value.checktable()
                    if (table.size() > MAX_ITEMS) throw LuaError("json table exceeds $MAX_ITEMS items")
                    val length = table.length()
                    val isArray = table.getmetatable() === jsonArrayMetatable ||
                        (length > 0 && length == table.size())
                    if (isArray) {
                        out.append('[')
                        for (index in 1..length) {
                            if (index > 1) out.append(',')
                            enforceItemLimit(itemCount)
                            appendJson(table.get(index), out, active, depth + 1, itemCount)
                        }
                        out.append(']')
                    } else {
                        val entries = ArrayList<Pair<String, LuaValue>>()
                        val keys = HashSet<String>()
                        var entry = table.next(LuaValue.NIL)
                        while (!entry.arg1().isnil()) {
                            enforceItemLimit(itemCount)
                            val key = entry.arg1().tojstring()
                            if (!keys.add(key)) throw LuaError("json object contains duplicate key '$key'")
                            entries += key to entry.arg(2)
                            entry = table.next(entry.arg1())
                        }
                        entries.sortBy { it.first }
                        out.append('{')
                        entries.forEachIndexed { index, item ->
                            if (index > 0) out.append(',')
                            appendJsonString(out, item.first)
                            out.append(':')
                            appendJson(item.second, out, active, depth + 1, itemCount)
                        }
                        out.append('}')
                    }
                } finally {
                    active.remove(value)
                }
            }
            else -> throw LuaError("json cannot encode ${value.typename()}")
        }
    }

    private fun decodeJson(text: String): LuaValue {
        if (text.toByteArray(StandardCharsets.UTF_8).size > MAX_UTILITY_BYTES) {
            throw LuaError("JSON input exceeds 1 MiB")
        }
        return JsonParser(text).parse()
    }

    private fun enforceItemLimit(itemCount: IntArray) {
        itemCount[0]++
        if (itemCount[0] > MAX_ITEMS) throw LuaError("json value exceeds $MAX_ITEMS items")
    }

    private fun inspectValue(
        value: LuaValue,
        active: IdentityHashMap<LuaValue, Boolean>,
        depth: Int,
        itemCount: IntArray
    ): String {
        if (value === jsonNull) return "json.null"
        if (value.isnil() || value.isboolean() || value.isnumber()) return value.tojstring()
        if (value.isstring()) {
            val text = value.tojstring()
            val bounded = if (text.length > MAX_INSPECT_STRING_CHARS) {
                text.substring(0, MAX_INSPECT_STRING_CHARS) + "...[truncated]"
            } else text
            return quoteJsonString(bounded)
        }
        if (!value.istable()) return "<${value.typename()}>"
        if (depth >= 12) return "<max-depth>"
        if (itemCount[0] >= MAX_INSPECT_ITEMS) return "<truncated>"
        if (active.put(value, true) != null) return "<cycle>"
        return try {
            val table = value.checktable()
            val entries = ArrayList<Pair<String, String>>()
            var entry = table.next(LuaValue.NIL)
            var count = 0
            while (!entry.arg1().isnil() && count < 200 && itemCount[0] < MAX_INSPECT_ITEMS) {
                itemCount[0]++
                entries += inspectKey(entry.arg1(), itemCount) to
                    inspectValue(entry.arg(2), active, depth + 1, itemCount)
                entry = table.next(entry.arg1())
                count++
            }
            entries.sortBy { it.first }
            val suffix = if (!entry.arg1().isnil()) listOf("..." to "") else emptyList()
            (entries + suffix).joinToString(prefix = "{", postfix = "}", separator = ", ") {
                if (it.first == "...") "..." else "${it.first} = ${it.second}"
            }
        } finally {
            active.remove(value)
        }
    }

    private fun inspectKey(value: LuaValue, itemCount: IntArray): String = when {
        value.isstring() && value.tojstring().matches(Regex("[A-Za-z_][A-Za-z0-9_]*")) -> value.tojstring()
        else -> "[${inspectValue(value, IdentityHashMap(), 0, itemCount)}]"
    }

    private fun deepEquals(left: LuaValue, right: LuaValue): Boolean =
        deepEquals(left, right, HashSet(), 0)

    private fun deepEquals(left: LuaValue, right: LuaValue, seen: MutableSet<Pair<LuaValue, LuaValue>>, depth: Int): Boolean {
        if (left === right || left.eq_b(right)) return true
        if (!left.istable() || !right.istable() || depth > MAX_DEPTH) return false
        val pair = left to right
        if (!seen.add(pair)) return true
        if (left.checktable().size() != right.checktable().size()) return false
        var entry = left.next(LuaValue.NIL)
        while (!entry.arg1().isnil()) {
            val rightValue = right.get(entry.arg1())
            if (rightValue.isnil() || !deepEquals(entry.arg(2), rightValue, seen, depth + 1)) return false
            entry = left.next(entry.arg1())
        }
        return true
    }

    private fun appendJsonString(out: StringBuilder, text: String) {
        out.append('"')
        for (char in text) {
            when (char) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\b' -> out.append("\\b")
                '\u000c' -> out.append("\\f")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> if (char.code < 0x20) out.append("\\u%04x".format(char.code)) else out.append(char)
            }
        }
        out.append('"')
    }

    private fun quoteJsonString(text: String): String = StringBuilder().also {
        appendJsonString(it, text)
    }.toString()

    private class JsonParser(private val text: String) {
        private var index = 0
        private var items = 0

        fun parse(): LuaValue {
            skipWhitespace()
            val value = parseValue(0)
            skipWhitespace()
            if (index != text.length) fail("unexpected trailing content")
            return value
        }

        private fun parseValue(depth: Int): LuaValue {
            if (depth > MAX_DEPTH) fail("maximum depth $MAX_DEPTH exceeded")
            skipWhitespace()
            return when (peek()) {
                '{' -> parseObject(depth)
                '[' -> parseArray(depth)
                '"' -> LuaValue.valueOf(parseString())
                't' -> { consumeLiteral("true"); LuaValue.TRUE }
                'f' -> { consumeLiteral("false"); LuaValue.FALSE }
                'n' -> { consumeLiteral("null"); jsonNull }
                '-', in '0'..'9' -> parseNumber()
                else -> fail("expected JSON value")
            }
        }

        private fun parseObject(depth: Int): LuaValue {
            expect('{')
            val table = LuaTable()
            val keys = HashSet<String>()
            skipWhitespace()
            if (consumeIf('}')) return table
            while (true) {
                skipWhitespace()
                if (peek() != '"') fail("object key must be a string")
                val key = parseString()
                if (!keys.add(key)) fail("duplicate object key '$key'")
                skipWhitespace()
                expect(':')
                countItem()
                table.set(key, parseValue(depth + 1))
                skipWhitespace()
                if (consumeIf('}')) return table
                expect(',')
            }
        }

        private fun parseArray(depth: Int): LuaValue {
            expect('[')
            val table = LuaTable().apply { setmetatable(jsonArrayMetatable) }
            skipWhitespace()
            if (consumeIf(']')) return table
            var arrayIndex = 1
            while (true) {
                countItem()
                table.set(arrayIndex++, parseValue(depth + 1))
                skipWhitespace()
                if (consumeIf(']')) return table
                expect(',')
            }
        }

        private fun parseString(): String {
            expect('"')
            val out = StringBuilder()
            while (index < text.length) {
                val char = text[index++]
                when {
                    char == '"' -> return out.toString()
                    char == '\\' -> {
                        if (index >= text.length) fail("unterminated escape")
                        when (val escaped = text[index++]) {
                            '"', '\\', '/' -> out.append(escaped)
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000c')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> out.append(parseUnicodeEscape())
                            else -> fail("invalid escape '$escaped'")
                        }
                    }
                    char.code < 0x20 -> fail("control character in string")
                    else -> out.append(char)
                }
            }
            fail("unterminated string")
        }

        private fun parseUnicodeEscape(): Char {
            if (index + 4 > text.length) fail("incomplete unicode escape")
            val digits = text.substring(index, index + 4)
            index += 4
            return digits.toIntOrNull(16)?.toChar() ?: fail("invalid unicode escape")
        }

        private fun parseNumber(): LuaValue {
            val start = index
            consumeIf('-')
            when {
                consumeIf('0') -> Unit
                peek() in '1'..'9' -> while (peek() in '0'..'9') index++
                else -> fail("invalid number")
            }
            var decimal = false
            if (consumeIf('.')) {
                decimal = true
                if (peek() !in '0'..'9') fail("invalid number fraction")
                while (peek() in '0'..'9') index++
            }
            if (peek() == 'e' || peek() == 'E') {
                decimal = true
                index++
                if (peek() == '+' || peek() == '-') index++
                if (peek() !in '0'..'9') fail("invalid number exponent")
                while (peek() in '0'..'9') index++
            }
            val number = text.substring(start, index)
            if (!decimal) number.toLongOrNull()?.let { return LuaValue.valueOf(it) }
            val double = number.toDoubleOrNull() ?: fail("invalid number")
            if (!double.isFinite()) fail("number is not finite")
            return LuaValue.valueOf(double)
        }

        private fun consumeLiteral(literal: String) {
            if (!text.regionMatches(index, literal, 0, literal.length)) fail("expected '$literal'")
            index += literal.length
        }

        private fun countItem() {
            items++
            if (items > MAX_ITEMS) fail("value exceeds $MAX_ITEMS items")
        }

        private fun skipWhitespace() {
            while (index < text.length && text[index] in charArrayOf(' ', '\t', '\r', '\n')) index++
        }

        private fun expect(expected: Char) {
            if (!consumeIf(expected)) fail("expected '$expected'")
        }

        private fun consumeIf(expected: Char): Boolean {
            if (peek() != expected) return false
            index++
            return true
        }

        private fun peek(): Char = if (index < text.length) text[index] else '\u0000'

        private fun fail(message: String): Nothing = throw LuaError("invalid JSON at position $index: $message")
    }
}

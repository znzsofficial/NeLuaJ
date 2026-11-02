package com.androlua.layout

/** A bounded, non-evaluating reader for literal layout tables, not a general Lua AST. */
internal class LayoutSource(private val source: String) {
    data class Token(val text: String, val kind: String, val line: Int, val column: Int, val literal: Any? = null)
    data class Value(val token: Token, val kind: String, val literal: Any? = null,
                     val fields: List<Field> = emptyList(), val expression: String = "")
    data class Field(val key: String?, val index: Int?, val token: Token, val value: Value)
    data class Root(val value: Value?, val token: Token, val reason: String? = null)
    private val tokens = ArrayList<Token>()
    private val pairs = HashMap<Int, Int>()
    private val unsupported = ArrayList<Token>()
    private fun Token.isSeparator(): Boolean = kind == "symbol" && text in listOf(",", ";")

    fun roots(): List<Root> {
        tokenize()
        val stack = ArrayList<Int>()
        for (i in tokens.indices) {
            val t = tokens[i]
            if (t.kind != "symbol") continue
            when (t.text) {
                "{", "(", "[" -> stack.add(i)
                "}", ")", "]" -> {
                    check(stack.isNotEmpty()) { "Unbalanced source at ${t.line}:${t.column}" }
                    val open = stack.removeAt(stack.lastIndex)
                    check(tokens[open].text == when (t.text) { "}" -> "{"; ")" -> "("; else -> "[" })
                    pairs[open] = i
                }
            }
            check(stack.size <= 64) { "Layout source exceeds 64 delimiter levels" }
        }
        val roots = ArrayList<Root>()
        val seen = HashSet<Int>()
        // Calls inside functions are inspected too, but never invoked. Table ranges belonging
        // to an already selected root are not rediscovered as separate return layouts.
        var coveredUntil = -1
        for (i in tokens.indices) {
            if (i <= coveredUntil) continue
            val token = tokens[i]
            if (token.kind != "name") continue
            val start = when {
                token.text == "return" -> i + 1
                token.text == "loadlayout" && tokens.getOrNull(i - 1)?.text !in listOf(".", ":", "function") ->
                    if (tokens.getOrNull(i + 1)?.text == "(") i + 2 else i + 1
                else -> continue
            }
            val first = tokens.getOrNull(start) ?: continue
            if (token.text == "return" && first.kind == "name" && first.text == "loadlayout") continue
            if (first.text == "{" && first.kind == "symbol") {
                val end = pairs[start] ?: continue
                // Ignore non-layout return values (e.g. {ok=true}); report an unknown rather
                // than treating arbitrary application data as an invalid View tree.
                val table = table(start, end, 0)
                if (seen.add(start)) roots.add(Root(table, token))
                coveredUntil = end
            } else if (token.text == "loadlayout" || token.text == "return") {
                roots.add(Root(null, first))
            }
            check(roots.size <= 256) { "Too many layout candidates (limit 256)" }
        }
        return roots + unsupported.map { Root(null, it, "Unsupported block expression; remaining fields cannot be inspected reliably") }
    }

    private fun table(start: Int, end: Int, depth: Int): Value {
        check(depth <= 48) { "Layout tables exceed 48 levels" }
        val fields = ArrayList<Field>()
        var pos = start + 1
        var index = 1
        while (pos < end) {
            if (tokens[pos].isSeparator()) { pos++; continue }
            val fieldToken = tokens[pos]
            var key: String? = null
            var fieldIndex: Int? = null
            if (tokens[pos].kind == "name" && tokens.getOrNull(pos + 1)?.text == "=") {
                key = tokens[pos].text
                pos += 2
            } else if (tokens[pos].text == "[" && pairs[pos]?.let { tokens.getOrNull(it + 1)?.text == "=" } == true) {
                val close = pairs.getValue(pos)
                val constant = value(pos + 1, close, depth)
                key = constant.literal as? String
                fieldIndex = (constant.literal as? Double)?.takeIf { it % 1.0 == 0.0 }?.toInt()
                pos = close + 2
            } else {
                fieldIndex = index++
            }
            val from = pos
            while (pos < end && !tokens[pos].isSeparator()) {
                pos = when {
                    pairs.containsKey(pos) -> pairs.getValue(pos) + 1
                    tokens[pos].kind == "name" && tokens[pos].text in setOf("function", "when", "switch", "try") -> skipBlock(pos, end)
                    tokens[pos].kind == "name" && tokens[pos].text == "lambda" ||
                        tokens[pos].kind == "symbol" && tokens[pos].text == "\\" -> skipLambdaParameters(pos, end)
                    else -> pos + 1
                }
            }
            fields.add(Field(key, fieldIndex, fieldToken, value(from, pos, depth)))
        }
        return Value(tokens[start], "table", fields = fields)
    }

    private fun skipLambdaParameters(start: Int, limit: Int): Int {
        var pos = start + 1
        while (pos < limit) {
            if (pairs.containsKey(pos)) { pos = pairs.getValue(pos) + 1; continue }
            if (tokens[pos].text == ":") return pos + 1
            if (tokens[pos].text in listOf("-", "=") && tokens.getOrNull(pos + 1)?.text == ">") return pos + 2
            pos++
        }
        unsupported.add(tokens[start])
        return limit
    }

    private fun skipBlock(start: Int, limit: Int): Int {
        val blocks = arrayListOf(tokens[start].text)
        var pos = start + 1
        val pendingDo = HashSet<Int>()
        while (pos < limit) {
            val t = tokens[pos]
            if (pairs.containsKey(pos)) {
                pos = pairs.getValue(pos) + 1
                continue
            }
            if (t.kind == "name") when (t.text) {
                "function", "if", "repeat", "switch", "when", "try" -> blocks.add(t.text)
                "for", "while" -> { blocks.add(t.text); pendingDo.add(blocks.lastIndex) }
                "do" -> if (!pendingDo.remove(blocks.lastIndex)) blocks.add("do")
                "end", "until" -> {
                    pendingDo.remove(blocks.lastIndex)
                    if (blocks.isNotEmpty()) blocks.removeAt(blocks.lastIndex)
                    if (blocks.isEmpty()) return pos + 1
                }
            }
            pos++
        }
        unsupported.add(tokens[start])
        return limit // Unsupported extension: keep the expression opaque, never guess a value.
    }

    private fun value(start: Int, end: Int, depth: Int): Value {
        val t = tokens.getOrNull(start) ?: Token("", "unknown", 1, 1)
        if (start >= end) return Value(t, "unknown")
        if (t.text == "{" && pairs[start] == end - 1) return table(start, end - 1, depth + 1)
        if (end == start + 1) {
            if (t.kind == "string" && t.literal != null) return Value(t, "string", t.literal)
            if (t.kind == "number" && t.literal != null) return Value(t, "number", t.literal)
            if (t.kind == "name" && t.text in listOf("true", "false")) return Value(t, "boolean", t.text == "true")
            if (t.kind == "name" && t.text == "nil") return Value(t, "nil")
        }
        if (end == start + 2 && t.text == "-" && tokens[start + 1].kind == "number") {
            return Value(t, "number", (tokens[start + 1].literal as? Double)?.let { -it })
        }
        val range = tokens.subList(start, end)
        val qualified = range.indices.all { i ->
            if (i % 2 == 0) range[i].kind == "name" && range[i].text !in setOf("function", "nil", "true", "false")
            else range[i].text == "."
        } && range.size % 2 == 1
        return Value(t, if (qualified) "name" else "unknown", expression = range.joinToString("") { it.text }.take(200))
    }

    private fun tokenize() {
        var pos = 0
        var line = 1
        var column = 1
        fun advance(end: Int) {
            while (pos < end) {
                if (source[pos++] == '\n') { line++; column = 1 } else column++
            }
        }
        fun longEnd(at: Int): Pair<Int, String>? {
            if (source.getOrNull(at) != '[') return null
            var p = at + 1
            while (source.getOrNull(p) == '=') p++
            if (source.getOrNull(p) != '[') return null
            val close = "]" + "=".repeat(p - at - 1) + "]"
            val finish = source.indexOf(close, p + 1)
            check(finish >= 0) { "Unterminated long string/comment at $line:$column" }
            var content = source.substring(p + 1, finish).replace("\r\n", "\n").replace('\r', '\n')
            if (content.startsWith('\n')) content = content.substring(1)
            return finish + close.length to content
        }
        while (pos < source.length) {
            check(tokens.size < 40_000) { "Layout source exceeds 40000 tokens" }
            val c = source[pos]
            if (c.isWhitespace() || (pos == 0 && c == '\uFEFF')) { advance(pos + 1); continue }
            if (source.startsWith("--", pos) || (pos == 0 && source.startsWith("#!", pos))) {
                val long = if (source.startsWith("--", pos)) longEnd(pos + 2) else null
                advance(long?.first ?: source.indexOf('\n', pos).let { if (it < 0) source.length else it })
                continue
            }
            val start = pos
            val startLine = line
            val startColumn = column
            var kind = "symbol"
            var literal: Any? = null
            var end = pos + 1
            val long = if (c == '[') longEnd(pos) else null
            when {
                long != null -> { kind = "string"; end = long.first; literal = long.second }
                c == '\'' || c == '"' -> {
                    kind = "string"
                    var p = pos + 1
                    val decoded = StringBuilder()
                    var known = true
                    while (p < source.length && source[p] != c) {
                        var ch = source[p++]
                        if (ch == '\\') {
                            check(p < source.length) { "Unterminated string" }
                            ch = source[p++]
                            when (ch) {
                                'a' -> decoded.append('\u0007'); 'b' -> decoded.append('\b')
                                'f' -> decoded.append('\u000c'); 'n' -> decoded.append('\n')
                                'r' -> decoded.append('\r'); 't' -> decoded.append('\t'); 'v' -> decoded.append('\u000b')
                                '\\', '\'', '"' -> decoded.append(ch)
                                '\n' -> decoded.append('\n')
                                '\r' -> { if (source.getOrNull(p) == '\n') p++; decoded.append('\n') }
                                'z' -> while (p < source.length && source[p].isWhitespace()) p++
                                else -> if (ch in '0'..'9') {
                                    var digits = ch.toString()
                                    while (digits.length < 3 && source.getOrNull(p) in '0'..'9') digits += source[p++]
                                    decoded.append(digits.toInt().toChar())
                                } else known = false
                            }
                        } else decoded.append(ch)
                    }
                    check(p < source.length) { "Unterminated string at $line:$column" }
                    end = p + 1
                    if (known) literal = decoded.toString()
                }
                c.isLetter() || c == '_' -> {
                    kind = "name"
                    while (end < source.length && (source[end].isLetterOrDigit() || source[end] == '_')) end++
                }
                c.isDigit() || (c == '.' && source.getOrNull(pos + 1)?.isDigit() == true) -> {
                    kind = "number"
                    // Keep non-decimal/extended numerals opaque unless they can be decoded exactly.
                    while (end < source.length) {
                        val ch = source[end]
                        if (ch.isLetterOrDigit() || ch == '.' && !source.startsWith("..", end) ||
                            ch in "+-" && source[end - 1] in "eEpP") end++ else break
                    }
                    val raw = source.substring(start, end)
                    literal = if (raw.startsWith("0x", true)) raw.substring(2).toLongOrNull(16)?.toDouble()
                        else raw.toDoubleOrNull()
                }
            }
            tokens.add(Token(source.substring(start, end), kind, startLine, startColumn, literal))
            advance(end)
        }
    }
}

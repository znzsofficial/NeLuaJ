package com.nekolaska.io

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.*
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

/** Process-wide, token-owned coordinator. Tokens deliberately have no thread affinity.
 *
 * The journal is authoritative; the history index and result files are replayable projections.
 * External writers must also use this coordinator for a strict compare-and-swap guarantee:
 * portable filesystem APIs cannot atomically compare a hash and rename a file.
 */
object FileMutationEngine {
    private const val MAX_BYTES = 1572864
    private const val MAX_FILES = 2000
    @Volatile private var owner = ""
    private val ownership = Any()
    internal var checkpoint: ((String) -> Unit)? = null
    private class Failure(val code: String, message: String) : IOException(message)
    private fun fail(code: String, message: String): Nothing = throw Failure(code, message)
    private fun hit(name: String) { checkpoint?.invoke(name) }
    private fun obj(vararg values: Pair<String, Any?>) = JSONObject().apply {
        values.forEach { (k, v) -> put(k, v ?: JSONObject.NULL) }
    }
    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun id() = UUID.randomUUID().toString()
    private fun own(token: String) { if (token.isEmpty() || token != owner) fail("LOCK_REQUIRED", "Invalid transaction token") }

    fun tryAcquire(requestId: String): String = synchronized(ownership) {
        if (owner.isNotEmpty()) return@synchronized ""
        owner = id()
        owner
    }
    fun release(token: String) = synchronized(ownership) { if (token.isNotEmpty() && token == owner) owner = "" }

    /** Only the well-known Android shared-storage prefix may be resolved through aliases.
     * Everything below that prefix, including the final component, is checked without following links. */
    private fun path(value: String): Path {
        var p = Paths.get(value)
        if (!p.isAbsolute) fail("INVALID_PATH", "Absolute path required")
        if (p.any { it.toString() == ".." }) fail("INVALID_PATH", "Parent traversal is not allowed")
        p = p.normalize()
        val android = (System.getProperty("java.vm.name", "") ?: "").contains("Dalvik", true)
        if (android) {
            val alias = listOf("/sdcard", "/storage/emulated/0").map { Paths.get(it) }
                .firstOrNull { p.startsWith(it) }
            if (alias != null) p = alias.toRealPath().resolve(alias.relativize(p))
        }
        var current = p.root
        for (part in p) {
            current = current.resolve(part)
            if (Files.isSymbolicLink(current)) fail("SYMLINK", "Symbolic link rejected: $current")
        }
        if (p.parent == null) fail("INVALID_PATH", "Filesystem root cannot be mutated")
        return p
    }

    private fun snap(p: Path): JSONObject {
        path(p.toString())
        val entries = JSONArray()
        var bytes = 0L
        var count = 0
        fun visit(node: Path, relative: String) {
            if (++count > MAX_FILES) fail("SNAPSHOT_LIMIT", "Snapshot exceeds 2000 entries")
            if (Files.isSymbolicLink(node)) fail("SYMLINK", "Symbolic link rejected: $node")
            if (Files.isDirectory(node, NOFOLLOW_LINKS)) {
                entries.put(obj("path" to relative, "kind" to "dir"))
                Files.newDirectoryStream(node).use { stream ->
                    stream.toList().sortedBy { it.fileName.toString() }.forEach {
                        visit(it, if (relative.isEmpty()) it.fileName.toString() else "$relative/${it.fileName}")
                    }
                }
            } else if (Files.isRegularFile(node, NOFOLLOW_LINKS)) {
                bytes += Files.size(node)
                if (bytes > MAX_BYTES) fail("SNAPSHOT_LIMIT", "Snapshot exceeds 1.5 MiB")
                val data = Files.newInputStream(node).use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        if (output.size() + n > MAX_BYTES) fail("SNAPSHOT_LIMIT", "File grew beyond snapshot budget")
                        output.write(buffer, 0, n)
                    }
                    output.toByteArray()
                }
                if (data.size > MAX_BYTES || data.size.toLong() != Files.size(node)) fail("CONFLICT", "File changed during snapshot")
                entries.put(obj("path" to relative, "kind" to "file", "contentBase64" to Base64.getEncoder().encodeToString(data)))
            } else fail("UNSUPPORTED_TYPE", "Not a regular file or directory: $node")
        }
        val kind = if (attributes(p) == null) "missing" else {
            visit(p, "")
            if (Files.isDirectory(p, NOFOLLOW_LINKS)) "dir" else "file"
        }
        return snapshot(kind, entries)
    }

    private fun attributes(p: Path): BasicFileAttributes? = try {
        Files.readAttributes(p, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
    } catch (e: NoSuchFileException) {
        val parent = p.parent
        if (parent != null) {
            val a = attributes(parent)
            if (a != null && !a.isDirectory) fail("NOT_DIRECTORY", "Parent is not a directory: $parent")
        }
        null
    }

    private fun snapshot(kind: String, entries: JSONArray): JSONObject {
        // Explicit framing avoids relying on JSONObject key iteration order for version identity.
        val digest = MessageDigest.getInstance("SHA-256")
        fun add(data: ByteArray) { digest.update(ByteBuffer.allocate(8).putLong(data.size.toLong()).array()); digest.update(data) }
        add(kind.toByteArray(Charsets.UTF_8))
        entries.objects().forEach { e ->
            add(e.getString("path").toByteArray(Charsets.UTF_8)); add(e.getString("kind").toByteArray(Charsets.UTF_8))
            if (e.getString("kind") == "file") add(Base64.getDecoder().decode(e.getString("contentBase64")))
        }
        return obj("kind" to kind, "entries" to entries, "version" to digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
    }
    private fun missing() = snapshot("missing", JSONArray())
    private fun version(s: JSONObject) = s.getString("version")
    private fun summary(s: JSONObject) = obj("version" to version(s), "kind" to s.getString("kind"))
    fun observe(path: String): String {
        val p = path(path)
        val s = snap(p)
        val result = obj("path" to p.toString(), "kind" to s.getString("kind"), "version" to version(s))
        if (s.getString("kind") == "file") {
            val encoded = s.getJSONArray("entries").getJSONObject(0).getString("contentBase64")
            result.put("contentBase64", encoded)
            val data = Base64.getDecoder().decode(encoded)
            try { result.put("text", Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(data)).toString()) } catch (_: Exception) { }
        } else if (s.getString("kind") == "dir") result.put("manifest", s.getJSONArray("entries"))
        return result.toString()
    }

    private fun syncDir(p: Path): Boolean = try {
        FileChannel.open(p, READ).use { it.force(true) }; true
    } catch (_: Exception) { false }
    private fun writeFile(p: Path, bytes: ByteArray) {
        FileChannel.open(p, CREATE_NEW, WRITE).use { c ->
            val buffer = ByteBuffer.wrap(bytes)
            while (buffer.hasRemaining()) c.write(buffer)
            c.force(true)
        }
    }
    private fun persist(p: Path, json: JSONObject): Boolean {
        if (p.fileName.toString().startsWith("tx-")) json.put("schemaVersion", 1)
        val temp = Files.createTempFile(p.parent, ".journal-", ".tmp")
        try {
            FileChannel.open(temp, WRITE, TRUNCATE_EXISTING).use { c ->
                val buffer = ByteBuffer.wrap(json.toString().toByteArray(Charsets.UTF_8))
                while (buffer.hasRemaining()) c.write(buffer)
                c.force(true)
            }
            Files.move(temp, p, ATOMIC_MOVE, REPLACE_EXISTING)
            return syncDir(p.parent)
        } finally { Files.deleteIfExists(temp) }
    }
    private fun read(p: Path): JSONObject {
        val safe = path(p.toString())
        if (Files.size(safe) > 16L * 1024 * 1024) fail("CORRUPT_JOURNAL", "Metadata exceeds budget")
        val j = JSONObject(String(Files.readAllBytes(safe), Charsets.UTF_8))
        if (p.fileName.toString().startsWith("tx-")) validateJournal(p, j)
        return j
    }
    private fun validateSnapshot(s: JSONObject) {
        fun bad(): Nothing = fail("CORRUPT_JOURNAL", "Invalid snapshot")
        val kind = s.getString("kind")
        if (kind !in listOf("missing", "file", "dir")) bad()
        val entries = s.getJSONArray("entries").objects()
        if (entries.size > MAX_FILES || (kind == "missing" && entries.isNotEmpty()) || (kind != "missing" && entries.isEmpty())) bad()
        val seen = mutableMapOf<String, String>(); var size = 0L
        entries.forEachIndexed { i, e ->
            val rel = e.getString("path"); val type = e.getString("kind")
            if (type !in listOf("file", "dir") || seen.containsKey(rel)) bad()
            if (i == 0) { if (rel != "" || type != kind) bad() }
            else {
                if (rel.isEmpty() || rel.contains('\u0000') || rel.contains('\\') || rel.contains(':') || rel.startsWith('/') || rel.split('/').any { it.isEmpty() || it == "." || it == ".." }) bad()
                if (seen[rel.substringBeforeLast('/', "")] != "dir") bad()
            }
            seen[rel] = type
            if (type == "file") {
                val encoded = e.getString("contentBase64")
                if (encoded.length > MAX_BYTES * 2) bad()
                size += Base64.getDecoder().decode(encoded).size
                if (size > MAX_BYTES) bad()
            }
        }
        if (kind == "file" && entries.size != 1) bad()
        if (version(snapshot(kind, s.getJSONArray("entries"))) != version(s)) bad()
    }
    private fun validateJournal(file: Path, j: JSONObject) {
        fun bad(): Nothing = fail("CORRUPT_JOURNAL", "Invalid journal: ${file.fileName}")
        if (j.getInt("schemaVersion") != 1) bad()
        if (j.getString("scopeId").isBlank() || j.getString("transactionId").isBlank() || journalPath(file.parent, j.getString("transactionId")) != file) bad()
        val state = j.getString("state")
        if (state !in listOf("PREPARED", "ROLLING_BACK", "RECOVERY_REQUIRED", "COMMITTED", "ROLLED_BACK", "REJECTED")) bad()
        val steps = j.getJSONArray("steps").objects()
        if (j.has("result")) {
            val r = j.getJSONObject("result")
            if (r.getString("transactionId") != j.getString("transactionId") || r.getString("scopeId") != j.getString("scopeId")) bad()
        }
        if (j.optBoolean("tombstone") || state == "REJECTED") {
            if (steps.isNotEmpty() || !j.has("result")) bad()
            return
        }
        if (j.getLong("sequence") <= 0) bad()
        if (j.getString("mode") !in listOf("execute", "undo", "redo")) bad()
        if (j.getString("mode") != "execute" && j.getString("historyId").isBlank()) bad()
        val op = j.getJSONObject("operation"); val kind = op.getString("kind")
        if (kind !in listOf("write", "mkdir", "delete", "rename")) bad()
        val logical = mutableListOf(path(op.getString("path")))
        if (kind == "rename") logical.add(path(op.getString("target")))
        if (steps.size != logical.size || logical.distinct().size != logical.size) bad()
        val reserved = Regex("\\.mutation-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(stage|backup)")
        val publications = mutableListOf<Path>()
        steps.forEachIndexed { i, step ->
            val p = path(step.getString("path")); val display = path(step.getString("displayPath"))
            if (display != logical[i] || !display.startsWith(p) || file.parent.startsWith(p) || p.startsWith(file.parent)) bad()
            publications.add(p)
            for (key in listOf("stage", "backup")) {
                val r = path(step.getString(key))
                if (r.parent != p.parent || !reserved.matches(r.fileName.toString()) || !r.fileName.toString().endsWith(".$key")) bad()
            }
            for (key in listOf("before", "after")) {
                val s = step.getJSONObject(key); validateSnapshot(s)
                val ls = step.getJSONObject(key + "Logical")
                val rel = p.relativize(display).joinToString("/")
                val entries = JSONArray()
                s.getJSONArray("entries").objects().filter { it.getString("path") == rel || it.getString("path").startsWith("$rel/") || rel.isEmpty() }.forEach { e ->
                    val copy = JSONObject(e.toString()); copy.put("path", if (rel.isEmpty()) e.getString("path") else e.getString("path").removePrefix(rel).removePrefix("/")); entries.put(copy)
                }
                val derived = snapshot(if (entries.length() == 0) "missing" else entries.getJSONObject(0).getString("kind"), entries)
                if (version(derived) != version(ls) || derived.getString("kind") != ls.getString("kind")) bad()
                if (p != display && s.getString("kind") != "missing") {
                    // Implicit-parent trees may contain only the logical subtree and its ancestors.
                    if (s.getJSONArray("entries").objects().any { e -> val r = e.getString("path"); r.isNotEmpty() && r != rel && !rel.startsWith("$r/") && !r.startsWith("$rel/") }) bad()
                }
            }
        }
        if (publications.distinct().size != publications.size || publications.any { a -> publications.any { b -> a != b && a.startsWith(b) } }) bad()
        val parents = j.getJSONArray("parents")
        if ((0 until parents.length()).map { path(parents.getString(it)) }.toSet() != publications.map { it.parent }.toSet()) bad()
    }
    private fun storage(value: String): Path {
        val p = path(value)
        Files.createDirectories(p)
        path(p.toString())
        return p
    }
    private fun journalPath(root: Path, transactionId: String) = root.resolve("tx-${hash(transactionId.toByteArray(Charsets.UTF_8))}.json")
    // Objects are sorted recursively; array order and string bytes remain significant.
    private fun canonical(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { JSONObject.quote(it) + ":" + canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
        is Number -> java.math.BigDecimal(value.toString()).stripTrailingZeros().toPlainString()
        is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
    private fun externalId(scope: String, request: String) = "external-" + hash(canonical(JSONArray().put(scope).put(request)).toByteArray(Charsets.UTF_8))
    private fun reservationPath(root: Path, tx: String): Path {
        if (!Regex("external-[0-9a-f]{64}").matches(tx)) fail("INVALID_REQUEST", "Invalid external transaction ID")
        return root.resolve("$tx.json")
    }
    private fun reservation(root: Path, tx: String, scope: String): JSONObject {
        val r = read(reservationPath(root, tx))
        if (r.getString("scopeId") != scope || r.getString("transactionId") != tx || externalId(scope, r.getString("requestId")) != tx) fail("SCOPE_MISMATCH", "Reservation identity mismatch")
        return r
    }
    private fun externalError(e: Exception) = obj("error" to obj("code" to (if (e is Failure) e.code else "IO_ERROR"), "message" to e.message)).toString()
    private fun persistExternalTerminal(root: Path, tx: String, scope: String, answer: JSONObject) {
        // These records participate in native replay/query without entering undo history.
        // Publish the authoritative tombstone before the reservation projection.
        persist(journalPath(root, tx), obj("transactionId" to tx, "scopeId" to scope,
            "state" to "REJECTED", "sequence" to nextSequence(root), "steps" to JSONArray(),
            "tombstone" to true, "result" to answer))
        hit("external:terminal")
    }

    /** A reservation without a journal is terminal on retry: preparation never runs twice.
     * Pending journals remain recoverable using recover; begin never re-publishes them. */
    @Synchronized fun beginExternal(token: String, storageDir: String, scopeId: String, requestId: String, requestJson: String): String = try {
        own(token)
        if (scopeId.isBlank() || requestId.isBlank()) fail("INVALID_REQUEST", "Scope and request ID are required")
        val digest = hash(canonical(JSONObject(requestJson)).toByteArray(Charsets.UTF_8))
        val root = storage(storageDir); val tx = externalId(scopeId, requestId); val rp = reservationPath(root, tx)
        if (Files.exists(rp)) {
            val r = reservation(root, tx, scopeId)
            if (r.getString("requestHash") != digest) fail("REQUEST_ID_REUSED", "Request ID was reserved for different content")
            val jp = journalPath(root, tx)
            val answer = if (Files.exists(jp)) existing(root, jp, scopeId) else r.optJSONObject("result") ?: result(tx, scopeId, "rejected", "REJECTED", Failure("INTERRUPTED", "Reserved request interrupted before publication; use a new request ID"))
            // Pending recovery observations must not become permanent terminal answers.
            if (!Files.exists(jp)) {
                persistExternalTerminal(root, tx, scopeId, answer)
                r.put("result", answer); persist(rp, r)
            }
            obj("transactionId" to tx, "result" to answer).toString()
        } else {
            persist(rp, obj("transactionId" to tx, "scopeId" to scopeId, "requestId" to requestId, "requestHash" to digest, "ownerToken" to token))
            hit("external:reserved")
            obj("transactionId" to tx).toString()
        }
    } catch (e: Exception) { externalError(e) }

    /** resultJson must contain scopeId and transactionId. Native journal facts always win. */
    @Synchronized fun finishExternal(token: String, storageDir: String, requestId: String, resultJson: String): String = try {
        own(token)
        val supplied = JSONObject(resultJson); val scope = supplied.getString("scopeId")
        val tx = externalId(scope, requestId); val root = storage(storageDir)
        if (supplied.getString("transactionId") != tx) fail("SCOPE_MISMATCH", "Result does not belong to reservation")
        val r = reservation(root, tx, scope); val jp = journalPath(root, tx)
        val answer = if (Files.exists(jp)) existing(root, jp, scope) else r.optJSONObject("result") ?: run {
            if (r.getString("ownerToken") != token) fail("INTERRUPTED", "Reservation belongs to an interrupted invocation")
            if (supplied.optString("commitState") !in listOf("REJECTED", "UNCHANGED") || supplied.optString("outcome") !in listOf("rejected", "unchanged") || supplied.optJSONArray("changes")?.length() != 0 || supplied.optBoolean("recoveryRequired")) fail("INVALID_RESULT", "A result without a journal cannot claim publication")
            supplied
        }
        if (!Files.exists(jp)) persistExternalTerminal(root, tx, scope, answer)
        r.put("result", answer); persist(reservationPath(root, tx), r)
        hit("external:finished")
        answer.toString()
    } catch (e: Exception) { externalError(e) }

    private fun externalGuard(root: Path, tx: String, scope: String, token: String): JSONObject? {
        if (!tx.startsWith("external-")) return null
        val r = reservation(root, tx, scope)
        r.optJSONObject("result")?.let { return it }
        if (r.getString("ownerToken") != token) fail("INTERRUPTED", "Retry via beginExternal before executing")
        return null
    }
    private fun journals(root: Path): List<Path> = Files.newDirectoryStream(root, "tx-*.json").use { it.toList().sortedBy { p -> read(p).optLong("sequence", 0) } }
    private fun nextSequence(root: Path): Long {
        val p = root.resolve("sequence.json")
        val previous = if (attributes(p) == null) 0L else read(p).getLong("value")
        val next = Math.addExact(previous, 1L)
        persist(p, obj("value" to next))
        return next
    }
    private fun blocked(root: Path, scope: String) = journals(root).any {
        val j = read(it)
        (j.getString("state") == "COMMITTED" && !j.has("result")) || (j.getString("scopeId") == scope && j.getString("state") !in listOf("COMMITTED", "ROLLED_BACK", "REJECTED"))
    }
    private fun result(tx: String, scope: String, outcome: String, state: String, error: Exception? = null) = obj(
        "transactionId" to tx, "scopeId" to scope, "outcome" to outcome, "commitState" to state,
        "changes" to JSONArray(), "history" to obj("recorded" to false, "persisted" to false),
        "durability" to obj("journal" to false, "directorySynced" to false, "atomic" to false),
        "warnings" to JSONArray()
    ).apply { if (error != null) put("error", obj("code" to (if (error is Failure) error.code else "IO_ERROR"), "message" to (error.message ?: error.javaClass.simpleName))) }

    /** Partial outcomes describe only effects verified at return time, including external edits.
     * They are observations, never a claim that every requested publication committed. */
    private fun actualEffects(j: JSONObject, r: JSONObject): JSONObject {
        val changes = JSONArray(); val unknown = JSONArray()
        val op = j.optJSONObject("operation")
        j.getJSONArray("steps").objects().forEach { step ->
            val displayPath = step.getString("displayPath")
            try {
                val before = step.getJSONObject("beforeLogical")
                val actual = snap(path(displayPath))
                if (version(before) != version(actual)) changes.put(obj(
                    "kind" to op?.optString("kind"), "path" to displayPath,
                    "from" to op?.optString("path"), "to" to op?.optString("target"),
                    "beforeVersion" to version(before), "afterVersion" to version(actual),
                    "beforeKind" to before.getString("kind"), "afterKind" to actual.getString("kind"),
                    "verified" to true, "publicationPath" to step.getString("path")))
            } catch (e: Exception) {
                unknown.put(obj("path" to displayPath, "code" to (if (e is Failure) e.code else "IO_ERROR"), "message" to e.message))
            }
        }
        r.put("changes", changes).put("recoveryRequired", true).put("unknownPaths", unknown)
        if (unknown.length() > 0) {
            if (!r.has("error")) r.put("error", obj("code" to "UNKNOWN_EFFECTS", "message" to "Some paths could not be observed"))
            r.getJSONObject("error").put("paths", unknown)
        }
        return r
    }

    @Synchronized fun execute(token: String, storageDir: String, requestJson: String): String {
        var tx = ""; var scope = ""
        return try {
            own(token)
            val request = JSONObject(requestJson)
            tx = request.getString("transactionId"); scope = request.getString("scopeId")
            require(tx.isNotBlank() && scope.isNotBlank())
            val root = storage(storageDir)
            val jp = journalPath(root, tx)
            if (Files.exists(jp)) return existing(root, jp, scope).toString()
            externalGuard(root, tx, scope, token)?.let { return it.toString() }
            if (blocked(root, scope)) fail("RECOVERY_REQUIRED", "Recover this scope before another operation")
            val op = request.getJSONObject("operation")
            val source = path(op.getString("path"))
            val kind = op.getString("kind")
            val paths = if (kind == "rename") listOf(source, path(op.getString("target"))) else listOf(source)
            if (paths.distinct().size != paths.size || (paths.size == 2 && (paths[0].startsWith(paths[1]) || paths[1].startsWith(paths[0])))) fail("INVALID_PATH", "Overlapping rename paths")
            paths.forEach { p ->
                if (root.startsWith(p) || p.startsWith(root)) fail("INVALID_PATH", "Mutation overlaps transaction storage")
                var ancestor = p.parent
                while (attributes(ancestor) == null) ancestor = ancestor.parent ?: fail("INVALID_PATH", "No existing ancestor")
                if (!Files.isDirectory(ancestor, NOFOLLOW_LINKS)) fail("NOT_DIRECTORY", "Parent is not a directory: $ancestor")
            }
            val before = paths.map(::snap)
            val expected = request.getJSONArray("expected").objects().associate { path(it.getString("path")).toString() to it.getString("version") }
            paths.forEachIndexed { i, p -> if (expected[p.toString()] != version(before[i])) fail("CONFLICT", "Missing or stale expected version: $p") }
            val after = when (kind) {
                "write" -> {
                    if (before[0].getString("kind") == "dir") fail("IS_DIRECTORY", "Cannot write over a directory")
                    val bytes = if (op.has("contentBase64")) Base64.getDecoder().decode(op.getString("contentBase64")) else op.getString("content").toByteArray(Charsets.UTF_8)
                    if (bytes.size > MAX_BYTES) fail("SNAPSHOT_LIMIT", "Content exceeds 1.5 MiB")
                    listOf(snapshot("file", JSONArray().put(obj("path" to "", "kind" to "file", "contentBase64" to Base64.getEncoder().encodeToString(bytes)))))
                }
                "mkdir" -> {
                    if (before[0].getString("kind") != "missing") fail("TARGET_EXISTS", "Target exists")
                    listOf(snapshot("dir", JSONArray().put(obj("path" to "", "kind" to "dir"))))
                }
                "delete" -> listOf(missing())
                "rename" -> {
                    if (before[0].getString("kind") == "missing") fail("SOURCE_MISSING", "Source missing")
                    if (before[1].getString("kind") != "missing") fail("TARGET_EXISTS", "Rename target exists")
                    listOf(missing(), before[0])
                }
                else -> fail("INVALID_OPERATION", "Unknown operation: $kind")
            }
            if (before.indices.all { version(before[it]) == version(after[it]) }) {
                val r = result(tx, scope, "unchanged", "UNCHANGED")
                persist(jp, obj("transactionId" to tx, "scopeId" to scope, "state" to "REJECTED", "steps" to JSONArray(), "result" to r))
                return r.toString()
            }
            transact(root, tx, scope, op, paths, before, after, "execute", "").toString()
        } catch (e: Exception) {
            var r = result(tx, scope, "rejected", "REJECTED", e)
            if (token.isNotEmpty() && token == owner && tx.isNotEmpty() && scope.isNotEmpty()) {
                try {
                    val root = storage(storageDir); val jp = journalPath(root, tx)
                    if (Files.exists(jp)) {
                        val j = read(jp)
                        if (j.getString("scopeId") == scope) r = j.optJSONObject("result") ?: actualEffects(j, result(tx, scope, "partial", j.getString("state"), e))
                    } else {
                        if (tx.startsWith("external-")) reservation(root, tx, scope)
                        persist(jp, obj("transactionId" to tx, "scopeId" to scope, "state" to "REJECTED", "steps" to JSONArray(), "result" to r))
                    }
                } catch (_: Exception) { r.getJSONArray("warnings").put("Result could not be persisted") }
            }
            r.toString()
        }
    }

    private fun materialize(p: Path, s: JSONObject) {
        if (s.getString("kind") == "missing") return
        s.getJSONArray("entries").objects().forEach { e ->
            val rel = e.getString("path")
            val dest = if (rel.isEmpty()) p else p.resolve(rel).normalize()
            if (!dest.startsWith(p)) fail("CORRUPT_JOURNAL", "Invalid manifest path")
            if (e.getString("kind") == "dir") Files.createDirectory(dest)
            else writeFile(dest, Base64.getDecoder().decode(e.getString("contentBase64")))
        }
        if (s.getString("kind") == "dir") Files.walk(p).use { stream -> stream.filter { Files.isDirectory(it, NOFOLLOW_LINKS) }.forEach { syncDir(it) } }
    }
    private fun erase(p: Path) {
        if (!Files.exists(p, NOFOLLOW_LINKS)) return
        if (Files.isDirectory(p, NOFOLLOW_LINKS)) Files.newDirectoryStream(p).use { it.forEach(::erase) }
        Files.delete(p)
    }
    private fun transact(root: Path, tx: String, scope: String, op: JSONObject, paths: List<Path>, before: List<JSONObject>, after: List<JSONObject>, mode: String, historyId: String, logical: List<JSONObject>? = null): JSONObject {
        val steps = JSONArray()
        val createdParents = JSONArray()
        paths.forEachIndexed { i, original ->
            var p = original
            var desired = after[i]
            if (before[i].getString("kind") == "missing" && desired.getString("kind") != "missing") {
                while (attributes(p.parent) == null) p = p.parent
                if (p != original) {
                    val entries = JSONArray()
                    val relative = p.relativize(original).joinToString("/")
                    var prefix = ""
                    entries.put(obj("path" to prefix, "kind" to "dir")); createdParents.put(p.toString())
                    val parts = relative.split('/')
                    for (part in parts.dropLast(1)) {
                        prefix = if (prefix.isEmpty()) part else "$prefix/$part"
                        entries.put(obj("path" to prefix, "kind" to "dir")); createdParents.put(p.resolve(prefix).toString())
                    }
                    desired.getJSONArray("entries").objects().forEach { e ->
                        val copy = JSONObject(e.toString())
                        copy.put("path", relative + if (e.getString("path").isEmpty()) "" else "/" + e.getString("path"))
                        entries.put(copy)
                    }
                    if (entries.length() > MAX_FILES) fail("SNAPSHOT_LIMIT", "Implicit parents exceed snapshot budget")
                    desired = snapshot("dir", entries)
                }
            }
            val display = logical?.get(i)
            steps.put(obj("path" to p.toString(), "before" to before[i], "after" to desired,
                "displayPath" to (display?.getString("displayPath") ?: original.toString()),
                "beforeLogical" to summary(display?.getJSONObject("beforeLogical") ?: before[i]),
                "afterLogical" to summary(display?.getJSONObject("afterLogical") ?: after[i]),
                "backup" to p.parent.resolve(".mutation-${id()}.backup").toString(), "stage" to p.parent.resolve(".mutation-${id()}.stage").toString()))
        }
        val publicationPaths = steps.objects().map { path(it.getString("path")) }
        if (publicationPaths.any { a -> publicationPaths.any { b -> a != b && a.startsWith(b) } }) fail("INVALID_PATH", "Implicit parents overlap another mutation path")
        val parents = JSONArray(publicationPaths.map { it.parent.toString() }.distinct())
        val operation = obj("kind" to op.getString("kind"), "path" to op.getString("path"))
        if (op.has("target")) operation.put("target", op.getString("target"))
        val j = obj("transactionId" to tx, "scopeId" to scope, "state" to "PREPARED", "operation" to operation,
            "sequence" to nextSequence(root),
            "steps" to steps, "parents" to parents, "createdParents" to createdParents, "mode" to mode, "historyId" to historyId, "directorySynced" to false)
        val jp = journalPath(root, tx)
        j.put("directorySynced", persist(jp, j))
        hit("prepared") // Error (rather than Exception) models process death in tests.
        try {
            // Validate the complete read set again immediately before the first publication.
            steps.objects().forEach { checkVersion(path(it.getString("path")), it.getJSONObject("before")) }
            steps.objects().forEachIndexed { index, step -> publish(step, index) }
            j.put("state", "COMMITTED")
            persist(jp, j)
            hit("committed")
            return finish(root, jp, j)
        } catch (e: Exception) {
            // A durable COMMITTED marker must never be compensated due to projection failure.
            if (j.getString("state") == "COMMITTED") {
                j.put("state", "COMMITTED")
                return actualEffects(j, result(tx, scope, "partial", "COMMITTED", e).put("warnings", JSONArray().put("Recovery must finish history/result projection")))
            }
            return compensate(root, jp, j, e)
        }
    }
    private fun checkVersion(p: Path, expected: JSONObject) {
        if (version(snap(p)) != version(expected)) fail("CONFLICT", "Version changed: $p")
    }
    private fun publish(step: JSONObject, index: Int) {
        val p = path(step.getString("path")); val stage = path(step.getString("stage")); val backup = path(step.getString("backup"))
        val before = step.getJSONObject("before"); val after = step.getJSONObject("after")
        materialize(stage, after)
        hit("staged:$index")
        checkVersion(p, before)
        // Files get one atomic replacement. Directory/removal publication uses an atomic move
        // into a reserved backup; a replacement directory may briefly be absent.
        if (before.getString("kind") == "file" && after.getString("kind") == "file") {
            Files.move(stage, p, ATOMIC_MOVE, REPLACE_EXISTING)
        } else {
            if (before.getString("kind") != "missing") Files.move(p, backup, ATOMIC_MOVE)
            hit("removed:$index")
            if (after.getString("kind") != "missing") Files.move(stage, p, ATOMIC_MOVE)
        }
        syncDir(p.parent)
        hit("published:$index")
        checkVersion(p, after)
    }

    private fun compensate(root: Path, jp: Path, j: JSONObject, cause: Exception): JSONObject {
        var complete = true
        j.put("state", "ROLLING_BACK")
        persist(jp, j)
        j.getJSONArray("steps").objects().asReversed().forEach { step ->
            try {
                val p = path(step.getString("path")); val before = step.getJSONObject("before"); val after = step.getJSONObject("after")
                val current = snap(p)
                if (version(current) != version(before)) {
                    val backup = path(step.getString("backup"))
                    val ownGap = current.getString("kind") == "missing" && Files.exists(backup, NOFOLLOW_LINKS) && version(snap(backup)) == version(before)
                    if (version(current) != version(after) && !ownGap) fail("EXTERNAL_CHANGE", "Cannot compensate externally modified path: $p")
                    val restoration = obj("path" to p.toString(), "before" to current, "after" to before,
                        "stage" to step.getString("stage"), "backup" to step.getString("backup"))
                    // Reuse the journal's reserved names so a second crash is also recognizable.
                    erase(path(step.getString("stage")))
                    if (Files.exists(backup, NOFOLLOW_LINKS)) {
                        if (version(snap(backup)) != version(before)) fail("EXTERNAL_CHANGE", "Backup changed")
                        if (current.getString("kind") != "missing") {
                            checkVersion(p, current)
                            Files.move(p, path(step.getString("stage")), ATOMIC_MOVE)
                        }
                        Files.move(backup, p, ATOMIC_MOVE)
                    } else publish(restoration, -1)
                }
            } catch (_: Exception) { complete = false }
        }
        j.put("state", if (complete) "ROLLED_BACK" else "RECOVERY_REQUIRED")
        val r = result(j.getString("transactionId"), j.getString("scopeId"), if (complete) "rolled_back" else "partial", j.getString("state"), cause)
        if (!complete) actualEffects(j, r)
        r.getJSONObject("durability").put("journal", true)
        j.put("result", r)
        try { persist(jp, j); if (complete) { cleanup(j); collectGarbage(root) } } catch (_: Exception) { r.getJSONArray("warnings").put("Recovery metadata or cleanup requires retry") }
        return r
    }
    private fun cleanup(j: JSONObject) {
        j.getJSONArray("steps").objects().forEach { step ->
            listOf("stage", "backup").forEach { key ->
                val p = path(step.getString(key))
                if (Files.exists(p, NOFOLLOW_LINKS)) {
                    val v = version(snap(p))
                    if (v == version(step.getJSONObject("before")) || v == version(step.getJSONObject("after"))) erase(p)
                }
            }
        }
    }
    private fun index(root: Path): JSONObject {
        val p = root.resolve("history.json")
        return if (Files.exists(p)) read(p) else obj("undo" to JSONArray(), "redo" to JSONArray(), "applied" to JSONArray())
    }
    private fun finish(root: Path, jp: Path, j: JSONObject): JSONObject {
        if (j.has("result")) { cleanup(j); return j.getJSONObject("result") }
        val tx = j.getString("transactionId")
        val idx = index(root)
        val applied = idx.getJSONArray("applied")
        val mode = j.getString("mode")
        if ((0 until applied.length()).none { applied.getString(it) == tx }) {
            if (mode == "execute") {
                idx.getJSONArray("undo").put(tx); idx.put("redo", JSONArray())
            } else {
                val from = idx.getJSONArray(mode)
                val expected = j.getString("historyId")
                if (from.length() == 0 || from.getString(from.length() - 1) != expected) fail("HISTORY_CONFLICT", "History head changed")
                from.remove(from.length() - 1)
                idx.getJSONArray(if (mode == "undo") "redo" else "undo").put(expected)
            }
            applied.put(tx)
            // Recovery journals are intentionally independent of this bounded user history.
            for (direction in listOf("undo", "redo")) {
                val stack = idx.getJSONArray(direction)
                var size = (0 until stack.length()).sumOf { Files.size(journalPath(root, stack.getString(it))) }
                while (stack.length() > 10 || size > 4L * 1024 * 1024) {
                    size -= Files.size(journalPath(root, stack.getString(0))); stack.remove(0)
                }
            }
            persist(root.resolve("history.json"), idx)
        }
        hit("history")
        val r = result(tx, j.getString("scopeId"), "committed", "COMMITTED")
        j.getJSONArray("steps").objects().forEach { step ->
            r.getJSONArray("changes").put(obj("kind" to j.getJSONObject("operation").getString("kind"), "path" to step.getString("displayPath"),
                "from" to j.getJSONObject("operation").optString("path"), "to" to j.getJSONObject("operation").optString("target"),
                "beforeVersion" to version(step.getJSONObject("beforeLogical")), "afterVersion" to version(step.getJSONObject("afterLogical")),
                "beforeKind" to step.getJSONObject("beforeLogical").getString("kind"), "afterKind" to step.getJSONObject("afterLogical").getString("kind")))
        }
        r.put("history", obj("recorded" to true, "persisted" to true))
        val synced = j.getJSONArray("parents").let { a -> (0 until a.length()).map { syncDir(path(a.getString(it))) }.all { it } }
        r.put("durability", obj("journal" to true, "directorySynced" to (synced && j.optBoolean("directorySynced")), "atomic" to (j.getJSONArray("steps").length() == 1)))
        if (!synced || !j.optBoolean("directorySynced")) r.getJSONArray("warnings").put("Directory fsync unavailable or unconfirmed")
        j.put("result", r)
        persist(jp, j)
        cleanup(j)
        collectGarbage(root)
        return r
    }
    private fun collectGarbage(root: Path) {
        val idx = index(root)
        val references = mutableSetOf<String>()
        for (direction in listOf("undo", "redo")) {
            val stack = idx.getJSONArray(direction)
            for (i in 0 until stack.length()) references.add(stack.getString(i))
        }
        val records = journals(root).map { it to read(it) }
        records.forEach { (_, j) ->
            if (!j.has("result") || j.getString("state") !in listOf("COMMITTED", "ROLLED_BACK", "REJECTED")) {
                references.add(j.getString("transactionId"))
                if (j.optString("historyId").isNotEmpty()) references.add(j.getString("historyId"))
            }
        }
        records.forEach { (p, j) ->
            if (!j.optBoolean("tombstone") && j.has("result") && j.getString("transactionId") !in references) {
                cleanup(j)
                persist(p, obj("transactionId" to j.getString("transactionId"), "scopeId" to j.getString("scopeId"),
                    "state" to j.getString("state"), "sequence" to j.optLong("sequence"), "steps" to JSONArray(),
                    "tombstone" to true, "result" to j.getJSONObject("result")))
            }
        }
        // A persisted result is itself the permanent projection/dedup marker. Only the
        // crash window between index publication and result publication needs applied IDs.
        val applied = idx.getJSONArray("applied")
        val pending = records.filter { (_, j) -> !j.has("result") }.map { it.second.getString("transactionId") }.toSet()
        idx.put("applied", JSONArray((0 until applied.length()).map { applied.getString(it) }.filter { it in pending }))
        persist(root.resolve("history.json"), idx)
    }
    private fun existing(root: Path, jp: Path, scope: String): JSONObject {
        val j = read(jp)
        if (j.getString("scopeId") != scope) fail("TRANSACTION_ID_REUSED", "Transaction belongs to another scope")
        return when (j.getString("state")) {
            "COMMITTED" -> finish(root, jp, j)
            "ROLLED_BACK", "REJECTED" -> j.getJSONObject("result")
            else -> actualEffects(j, result(j.getString("transactionId"), scope, "partial", "RECOVERY_REQUIRED", Failure("RECOVERY_REQUIRED", "Run recovery")))
        }
    }
    @Synchronized fun peek(storageDir: String, direction: String): String {
        require(direction == "undo" || direction == "redo")
        val root = storage(storageDir); val stack = index(root).getJSONArray(direction)
        if (stack.length() == 0) return "null"
        val tx = stack.getString(stack.length() - 1); val j = read(journalPath(root, tx))
        return obj("id" to tx, "operation" to j.getJSONObject("operation"), "scopeId" to j.getString("scopeId")).toString()
    }
    @Synchronized fun history(token: String, storageDir: String, scopeId: String, direction: String, expectedId: String): String {
        return historyWithId(token, storageDir, scopeId, direction, expectedId, id())
    }
    @Synchronized fun historyExternal(token: String, storageDir: String, scopeId: String, direction: String, expectedId: String, transactionId: String): String {
        return historyWithId(token, storageDir, scopeId, direction, expectedId, transactionId, true)
    }
    private fun historyWithId(token: String, storageDir: String, scopeId: String, direction: String, expectedId: String, tx: String, external: Boolean = false): String {
        return try {
            own(token)
            require(direction == "undo" || direction == "redo")
            val root = storage(storageDir)
            if (external) {
                reservation(root, tx, scopeId)
                val jp = journalPath(root, tx)
                if (Files.exists(jp)) return existing(root, jp, scopeId).toString()
                externalGuard(root, tx, scopeId, token)?.let { return it.toString() }
            }
            if (blocked(root, scopeId)) fail("RECOVERY_REQUIRED", "Run recovery first")
            val stack = index(root).getJSONArray(direction)
            if (stack.length() == 0 || stack.getString(stack.length() - 1) != expectedId) fail("HISTORY_CONFLICT", "History head changed")
            val original = read(journalPath(root, expectedId))
            if (original.getString("scopeId") != scopeId) fail("SCOPE_MISMATCH", "History belongs to another scope")
            val steps = original.getJSONArray("steps").objects()
            val before = steps.map { it.getJSONObject(if (direction == "undo") "after" else "before") }
            val after = steps.map { it.getJSONObject(if (direction == "undo") "before" else "after") }
            val paths = steps.map { path(it.getString("path")) }
            paths.forEachIndexed { i, p -> checkVersion(p, before[i]) }
            val logical = steps.map { step -> obj("displayPath" to step.getString("displayPath"),
                "beforeLogical" to step.getJSONObject(if (direction == "undo") "afterLogical" else "beforeLogical"),
                "afterLogical" to step.getJSONObject(if (direction == "undo") "beforeLogical" else "afterLogical")) }
            transact(root, tx, scopeId, original.getJSONObject("operation"), paths, before, after, direction, expectedId, logical).toString()
        } catch (e: Exception) {
            var r = result(tx, scopeId, "rejected", "REJECTED", e)
            try {
                if (token.isNotEmpty() && token == owner) {
                    val jp = journalPath(storage(storageDir), tx)
                    if (Files.exists(jp)) {
                        val j = read(jp)
                        if (j.getString("scopeId") == scopeId) r = j.optJSONObject("result") ?: actualEffects(j, result(tx, scopeId, "partial", j.getString("state"), e))
                    } else if (external) {
                        reservation(jp.parent, tx, scopeId)
                        persist(jp, obj("transactionId" to tx, "scopeId" to scopeId, "state" to "REJECTED", "steps" to JSONArray(), "result" to r))
                    }
                }
            } catch (_: Exception) { }
            r.toString()
        }
    }
    @Synchronized fun recover(token: String, storageDir: String, scopeId: String): String {
        val reports = JSONArray()
        return try {
            own(token)
            val root = storage(storageDir)
            journals(root).forEach { jp ->
                val j = read(jp)
                if (j.getString("scopeId") == scopeId) {
                    when (j.getString("state")) {
                        "COMMITTED" -> if (!j.has("result")) reports.put(finish(root, jp, j))
                        "ROLLED_BACK", "REJECTED" -> cleanup(j)
                        else -> {
                            val allAfter = j.getJSONArray("steps").objects().all { version(snap(path(it.getString("path")))) == version(it.getJSONObject("after")) }
                            if (allAfter && j.getString("state") == "PREPARED") { j.put("state", "COMMITTED"); persist(jp, j); reports.put(finish(root, jp, j)) }
                            else reports.put(compensate(root, jp, j, Failure("INTERRUPTED", "Interrupted transaction")))
                        }
                    }
                }
            }
            collectGarbage(root)
            obj("scopeId" to scopeId, "recovered" to !blocked(root, scopeId), "results" to reports).toString()
        } catch (e: Exception) { obj("scopeId" to scopeId, "recovered" to false, "results" to reports, "error" to obj("code" to (if (e is Failure) e.code else "IO_ERROR"), "message" to e.message)).toString() }
    }
    @Synchronized fun getResult(storageDir: String, transactionId: String): String {
        val p = journalPath(storage(storageDir), transactionId)
        if (!Files.exists(p)) return "null"
        val j = read(p)
        return j.optJSONObject("result")?.toString() ?: actualEffects(j, result(transactionId, j.getString("scopeId"), "partial", j.getString("state"))).toString()
    }

    /** Durable UI replay source, including compacted result tombstones. The Lua service
     * owns acknowledgements; reading this list never acknowledges or mutates a result. */
    @Synchronized fun listResults(storageDir: String, scopeId: String): String {
        val root = storage(storageDir)
        val results = JSONArray()
        journals(root).forEach { file ->
            val journal = read(file)
            if (journal.getString("scopeId") == scopeId) {
                journal.optJSONObject("result")?.let { results.put(it) }
            }
        }
        return results.toString()
    }

    /** Imports only validated history data. No operation here publishes into the project. */
    @Synchronized fun importLegacy(token: String, storageDir: String, scopeId: String, legacyJson: String): String {
        val warnings = JSONArray()
        return try {
            own(token)
            if (legacyJson.toByteArray(Charsets.UTF_8).size > 4 * 1024 * 1024) fail("LEGACY_LIMIT", "Legacy source exceeds 4 MiB")
            val root = storage(storageDir)
            val sourceHash = hash(legacyJson.toByteArray(Charsets.UTF_8))
            val migrationId = hash((scopeId + "\n" + sourceHash).toByteArray(Charsets.UTF_8))
            val marker = root.resolve("migration-$migrationId.json")
            if (attributes(marker) != null) return read(marker).toString()
            val idx = index(root)
            if (idx.optString("migrationId") == migrationId) {
                val done = obj("imported" to true, "migratedCount" to (idx.getJSONArray("undo").length() + idx.getJSONArray("redo").length()), "warnings" to JSONArray().put("Legacy text snapshots restore only their stored UTF-8 representation"))
                persist(marker, done)
                return done.toString()
            }
            if (idx.getJSONArray("undo").length() > 0 || idx.getJSONArray("redo").length() > 0 || blocked(root, scopeId)) fail("HISTORY_EXISTS", "Existing native history is preserved; legacy source must remain isolated")
            if (journals(root).any { read(it).optString("legacyImport") != migrationId }) fail("HISTORY_EXISTS", "Native records already exist; legacy source must remain isolated")
            val source = JSONObject(legacyJson)
            val scope = path(scopeId)
            fun scoped(value: String): Path {
                val p = path(value)
                if (!p.startsWith(scope) || p == scope || root.startsWith(p) || p.startsWith(root)) fail("LEGACY_SCOPE", "Legacy path is outside scope: $p")
                return p
            }
            var textWarning = false
            fun convert(old: JSONObject, expected: Path): JSONObject {
                if (scoped(old.getString("path")) != expected) fail("LEGACY_PATH", "Snapshot path does not match operation")
                val kind = old.getString("kind")
                if (kind == "missing") return missing()
                val entries = mutableMapOf<String, JSONObject>()
                fun file(e: JSONObject, relative: String) {
                    if (e.getString("kind") != "file") fail("LEGACY_SCHEMA", "Directory files must be regular files")
                    val content = e.getString("content")
                    val bytes = when (e.optString("encoding")) {
                        "base64" -> {
                            if (content.length % 4 != 0 || !Regex("[A-Za-z0-9+/]*={0,2}").matches(content)) fail("LEGACY_ENCODING", "Invalid base64")
                            Base64.getDecoder().decode(content).also { if (Base64.getEncoder().encodeToString(it) != content) fail("LEGACY_ENCODING", "Non-canonical base64") }
                        }
                        "" -> { textWarning = true; content.toByteArray(Charsets.UTF_8) }
                        else -> fail("LEGACY_ENCODING", "Unsupported legacy encoding")
                    }
                    if (entries.containsKey(relative)) fail("LEGACY_PATH", "Duplicate manifest entry")
                    entries[relative] = obj("path" to relative, "kind" to "file", "contentBase64" to Base64.getEncoder().encodeToString(bytes))
                }
                if (kind == "file") file(old, "")
                else if (kind == "dir") {
                    entries[""] = obj("path" to "", "kind" to "dir")
                    fun relative(value: String): String {
                        val child = scoped(value)
                        if (child == expected || !child.startsWith(expected)) fail("LEGACY_PATH", "Manifest child outside root")
                        return expected.relativize(child).joinToString("/")
                    }
                    val dirs = old.getJSONArray("dirs")
                    for (i in 0 until dirs.length()) {
                        val rel = relative(dirs.getString(i))
                        if (entries.containsKey(rel)) fail("LEGACY_PATH", "Duplicate directory")
                        entries[rel] = obj("path" to rel, "kind" to "dir")
                    }
                    old.getJSONArray("files").objects().forEach { file(it, relative(it.getString("path"))) }
                    for (rel in entries.keys.toList()) {
                        var parent = rel.substringBeforeLast('/', "")
                        while (parent.isNotEmpty()) {
                            val existing = entries[parent]
                            if (existing != null && existing.getString("kind") != "dir") fail("LEGACY_PATH", "File used as parent")
                            entries.putIfAbsent(parent, obj("path" to parent, "kind" to "dir"))
                            parent = parent.substringBeforeLast('/', "")
                        }
                    }
                } else fail("LEGACY_SCHEMA", "Unsupported snapshot kind")
                // Match snap's depth-first lexical traversal, rather than dirs-first ordering.
                val ordered = JSONArray()
                fun visit(rel: String) {
                    val e = entries.getValue(rel); ordered.put(e)
                    if (e.getString("kind") == "dir") entries.keys.filter { it.isNotEmpty() && it.substringBeforeLast('/', "") == rel }.sorted().forEach(::visit)
                }
                visit("")
                return snapshot(kind, ordered).also(::validateSnapshot)
            }
            val projection = obj("undo" to JSONArray(), "redo" to JSONArray(), "applied" to JSONArray(), "migrationId" to migrationId)
            val records = mutableListOf<Pair<Path, JSONObject>>()
            var count = 0
            for (direction in listOf("undo", "redo")) {
                val oldStack = source.getJSONArray(direction)
                if (oldStack.length() > 10) fail("LEGACY_LIMIT", "Legacy stack exceeds 10 entries")
                oldStack.objects().forEachIndexed { index, old ->
                    if (old.getString("scope") != scopeId) fail("LEGACY_SCOPE", "Legacy scope mismatch; source remains isolated")
                    old.getString("id")
                    val args = old.getJSONObject("args")
                    val kind = when (old.getString("name")) {
                        "create_file", "write_file", "edit_file", "patch_file", "replace_in_file", "apply_patch", "append_file" -> "write"
                        "create_directory", "create_dir", "mkdir" -> "mkdir"
                        "delete_file", "delete_directory" -> "delete"
                        "rename_file" -> "rename"
                        else -> fail("LEGACY_OPERATION", "Unsupported legacy operation")
                    }
                    val paths = mutableListOf(scoped(args.getString("path")))
                    if (kind == "rename") paths.add(scoped(args.getString("new_path")))
                    val before = old.getJSONArray("before"); val after = old.getJSONArray("after")
                    if (before.length() != paths.size || after.length() != paths.size) fail("LEGACY_SCHEMA", "Snapshot count mismatch")
                    val steps = JSONArray()
                    paths.forEachIndexed { n, p ->
                        val b = convert(before.getJSONObject(n), p); val a = convert(after.getJSONObject(n), p)
                        steps.put(obj("path" to p.toString(), "displayPath" to p.toString(), "before" to b, "after" to a,
                            "beforeLogical" to summary(b), "afterLogical" to summary(a),
                            "stage" to p.parent.resolve(".mutation-${id()}.stage").toString(), "backup" to p.parent.resolve(".mutation-${id()}.backup").toString()))
                    }
                    for (side in listOf("before", "after")) {
                        val entries = steps.objects().flatMap { it.getJSONObject(side).getJSONArray("entries").objects() }
                        if (entries.size > MAX_FILES || entries.sumOf { if (it.getString("kind") == "file") Base64.getDecoder().decode(it.getString("contentBase64")).size.toLong() else 0L } > MAX_BYTES) fail("LEGACY_LIMIT", "Transaction snapshot exceeds budget")
                    }
                    val b = steps.getJSONObject(0).getJSONObject("before")
                    val a = steps.getJSONObject(0).getJSONObject("after")
                    when (kind) {
                        "write" -> if (a.getString("kind") != "file" || b.getString("kind") == "dir") fail("LEGACY_SCHEMA", "Invalid write snapshots")
                        "mkdir" -> if (a.getString("kind") != "dir" || b.getString("kind") != "missing") fail("LEGACY_SCHEMA", "Invalid mkdir snapshots")
                        "delete" -> if (a.getString("kind") != "missing") fail("LEGACY_SCHEMA", "Invalid delete snapshots")
                        "rename" -> if (a.getString("kind") != "missing" || b.getString("kind") == "missing" || steps.getJSONObject(1).getJSONObject("before").getString("kind") != "missing" || version(steps.getJSONObject(1).getJSONObject("after")) != version(b)) fail("LEGACY_SCHEMA", "Invalid rename snapshots")
                    }
                    val tx = "legacy-$migrationId-$direction-$index"
                    val op = obj("kind" to kind, "path" to paths[0].toString())
                    if (paths.size == 2) op.put("target", paths[1].toString())
                    val r = result(tx, scopeId, "unchanged", "COMMITTED").put("legacyImported", true)
                    r.put("history", obj("recorded" to true, "persisted" to true))
                    val j = obj("schemaVersion" to 1, "transactionId" to tx, "scopeId" to scopeId, "state" to "COMMITTED", "sequence" to nextSequence(root),
                        "operation" to op, "steps" to steps, "parents" to JSONArray(paths.map { it.parent.toString() }.distinct()),
                        "mode" to "execute", "historyId" to "", "result" to r, "directorySynced" to false, "legacyImport" to migrationId)
                    val jp = journalPath(root, tx)
                    validateJournal(jp, j)
                    records.add(jp to j)
                    projection.getJSONArray(direction).put(tx); count++
                }
            }
            if (records.sumOf { it.second.toString().toByteArray(Charsets.UTF_8).size.toLong() } > 4L * 1024 * 1024) fail("LEGACY_LIMIT", "Converted history exceeds 4 MiB")
            if (textWarning) warnings.put("Legacy text snapshots restore only stored UTF-8 text; previously damaged original bytes cannot be recovered")
            // All validation completes before any imported journal is published. On a crash,
            // deterministic IDs allow retry; the single atomic index is the activation point.
            records.forEach { (p, j) -> persist(p, j) }
            hit("legacy-journals")
            persist(root.resolve("history.json"), projection)
            hit("legacy-projection")
            val done = obj("imported" to true, "migratedCount" to count, "warnings" to warnings)
            persist(marker, done)
            done.toString()
        } catch (e: Exception) {
            obj("imported" to false, "migratedCount" to 0, "warnings" to warnings,
                "error" to obj("code" to (if (e is Failure) e.code else "LEGACY_INVALID"), "message" to e.message)).toString()
        }
    }
    fun saveText(token: String, path: String, text: String, expectedVersion: String): String {
        val local = if (token.isEmpty()) tryAcquire("editor") else token
        var published = false
        var beforeSnapshot: JSONObject? = null
        return try {
            own(local)
            val p = path(path); val before = snap(p)
            beforeSnapshot = before
            if (before.getString("kind") == "dir") fail("IS_DIRECTORY", "Cannot save over directory")
            if (version(before) != expectedVersion) fail("CONFLICT", "Editor version changed")
            val bytes = text.toByteArray(Charsets.UTF_8)
            if (bytes.size > MAX_BYTES) fail("SNAPSHOT_LIMIT", "Content exceeds 1.5 MiB")
            val written = snapshot("file", JSONArray().put(obj("path" to "", "kind" to "file", "contentBase64" to Base64.getEncoder().encodeToString(bytes))))
            val temp = Files.createTempFile(p.parent, ".save-", ".tmp")
            var synced = false
            try {
                FileChannel.open(temp, WRITE, TRUNCATE_EXISTING).use { c ->
                    val b = ByteBuffer.wrap(bytes); while (b.hasRemaining()) c.write(b); c.force(true)
                }
                hit("save-staged")
                checkVersion(p, before)
                Files.move(temp, p, ATOMIC_MOVE, REPLACE_EXISTING)
                published = true; synced = syncDir(p.parent)
                hit("save-published")
                checkVersion(p, written)
            } finally { Files.deleteIfExists(temp) }
            result("", "", "committed", "COMMITTED").apply {
                put("version", version(written))
                put("durability", obj("journal" to false, "directorySynced" to synced, "atomic" to true))
                getJSONArray("changes").put(obj("kind" to "write", "path" to p.toString(), "beforeVersion" to expectedVersion, "afterVersion" to version(written), "beforeKind" to before.getString("kind"), "afterKind" to "file"))
            }.toString()
        } catch (e: Exception) {
            val r = result("", "", if (published) "partial" else "rejected", if (published) "COMMITTED" else "REJECTED", e)
            if (published) {
                try {
                    val p = path(path); val actual = snap(p)
                    r.put("observedVersion", version(actual))
                    r.getJSONArray("changes").put(obj("kind" to "write", "path" to p.toString(), "beforeVersion" to expectedVersion,
                        "afterVersion" to version(actual), "beforeKind" to beforeSnapshot?.getString("kind"), "afterKind" to actual.getString("kind"), "verified" to true))
                } catch (unknown: Exception) {
                    r.put("unknownPaths", JSONArray().put(obj("path" to path, "code" to "UNKNOWN_EFFECTS", "message" to unknown.message)))
                }
            }
            r.toString()
        }
        finally { if (token.isEmpty()) release(local) }
    }
}

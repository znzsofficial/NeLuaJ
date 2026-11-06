package com.nekolaska.io

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.Assume.assumeNoException
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.util.Base64
import java.util.UUID

class FileMutationEngineTest {
    private lateinit var dir: Path
    private lateinit var store: Path
    private lateinit var token: String
    private val engine = FileMutationEngine
    private class Crash : Error()
    @Before fun setup() {
        dir = Files.createTempDirectory("mutation-test-").toRealPath()
        store = dir.resolve("journal")
        token = engine.tryAcquire("test")
        assertNotEquals("", token)
    }
    @After fun teardown() {
        engine.checkpoint = null
        engine.release(token)
        Files.walk(dir).use { stream -> stream.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) } }
    }
    private fun observe(p: Path) = JSONObject(engine.observe(p.toString()))
    private fun version(p: Path) = observe(p).getString("version")
    private fun request(kind: String, p: Path, target: Path? = null, bytes: ByteArray = byteArrayOf(1, 2, 3), tx: String = UUID.randomUUID().toString()): JSONObject {
        val op = JSONObject().put("kind", kind).put("path", p.toString())
        if (kind == "write") op.put("contentBase64", Base64.getEncoder().encodeToString(bytes))
        if (target != null) op.put("target", target.toString())
        val expected = JSONArray().put(JSONObject().put("path", p.toString()).put("version", version(p)))
        if (target != null) expected.put(JSONObject().put("path", target.toString()).put("version", version(target)))
        return JSONObject().put("transactionId", tx).put("scopeId", "scope").put("operation", op).put("expected", expected)
    }
    private fun execute(r: JSONObject) = JSONObject(engine.execute(token, store.toString(), r.toString()))
    private fun history(direction: String, tx: String) = JSONObject(engine.history(token, store.toString(), "scope", direction, tx))
    private fun recover() = JSONObject(engine.recover(token, store.toString(), "scope"))
    private fun outcome(r: JSONObject, expected: String) = assertEquals(r.toString(), expected, r.getString("outcome"))

    @Test fun staleVersionAndExistingTargetNeverPublish() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(1))
        val req = request("write", p)
        Files.write(p, byteArrayOf(9))
        outcome(execute(req), "rejected")
        assertArrayEquals(byteArrayOf(9), Files.readAllBytes(p))
        assertEquals("rejected", JSONObject(engine.getResult(store.toString(), req.getString("transactionId"))).getString("outcome"))
        val target = dir.resolve("b"); Files.write(target, byteArrayOf(7))
        assertEquals("TARGET_EXISTS", execute(request("rename", p, target)).getJSONObject("error").getString("code"))
        assertArrayEquals(byteArrayOf(7), Files.readAllBytes(target))
    }
    @Test fun binaryDirectoryDeleteUndoRedoAndDeduplication() {
        val p = dir.resolve("tree"); Files.createDirectory(p)
        Files.createDirectory(p.resolve("empty"))
        val binary = byteArrayOf(0, -1, -128, 13, 10)
        Files.write(p.resolve("binary"), binary)
        val req = request("delete", p); val tx = req.getString("transactionId")
        outcome(execute(req), "committed")
        outcome(execute(req), "committed")
        assertFalse(Files.exists(p))
        outcome(history("undo", tx), "committed")
        assertArrayEquals(binary, Files.readAllBytes(p.resolve("binary")))
        assertTrue(Files.isDirectory(p.resolve("empty")))
        assertEquals("null", engine.peek(store.toString(), "undo"))
        outcome(history("undo", tx), "rejected")
        outcome(history("redo", tx), "committed")
        assertFalse(Files.exists(p))
        assertTrue(recover().getBoolean("recovered"))
        assertEquals(tx, JSONObject(engine.peek(store.toString(), "undo")).getString("id"))
    }
    @Test fun renamePartialFailureRestoresBytes() {
        val p = dir.resolve("a"); val target = dir.resolve("b")
        val binary = byteArrayOf(-1, 0, 3)
        Files.write(p, binary)
        val req = request("rename", p, target)
        engine.checkpoint = { if (it == "published:0") throw IOException("injected") }
        outcome(execute(req), "rolled_back")
        assertArrayEquals(binary, Files.readAllBytes(p))
        assertFalse(Files.exists(target))
    }
    @Test fun compensationDoesNotOverwriteExternalChangeAndBlocksScope() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(1))
        val req = request("write", p)
        engine.checkpoint = { if (it == "published:0") { Files.write(p, byteArrayOf(8)); throw IOException("external writer") } }
        val partial = execute(req)
        outcome(partial, "partial")
        assertTrue(partial.getBoolean("recoveryRequired"))
        val change = partial.getJSONArray("changes").getJSONObject(0)
        assertEquals(p.toString(), change.getString("path"))
        assertEquals(version(p), change.getString("afterVersion"))
        assertEquals("file", change.getString("afterKind"))
        engine.checkpoint = null
        assertArrayEquals(byteArrayOf(8), Files.readAllBytes(p))
        assertFalse(recover().getBoolean("recovered"))
        val rejected = execute(request("write", dir.resolve("other")))
        assertEquals("RECOVERY_REQUIRED", rejected.getJSONObject("error").getString("code"))
    }
    @Test fun preparedCrashRollsBackAndPublishedCrashCommitsIdempotently() {
        for (point in listOf("prepared", "published:0", "committed", "history")) {
            val p = dir.resolve(point.replace(':', '-'))
            Files.write(p, byteArrayOf(0))
            val req = request("write", p)
            engine.checkpoint = { if (it == point) throw Crash() }
            try { execute(req); fail("Crash not injected") } catch (_: Crash) { }
            engine.checkpoint = null
            assertTrue(recover().toString(), recover().getBoolean("recovered"))
            assertTrue(recover().getBoolean("recovered"))
            val r = JSONObject(engine.getResult(store.toString(), req.getString("transactionId")))
            outcome(r, if (point == "prepared") "rolled_back" else "committed")
            assertArrayEquals(if (point == "prepared") byteArrayOf(0) else byteArrayOf(1, 2, 3), Files.readAllBytes(p))
        }
    }
    @Test fun undoCrashAfterHistoryProjectionDoesNotDoublePop() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(0))
        val req = request("write", p); outcome(execute(req), "committed")
        engine.checkpoint = { if (it == "history") throw Crash() }
        try { history("undo", req.getString("transactionId")); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertTrue(recover().getBoolean("recovered"))
        assertTrue(recover().getBoolean("recovered"))
        assertEquals("null", engine.peek(store.toString(), "undo"))
        assertEquals(req.getString("transactionId"), JSONObject(engine.peek(store.toString(), "redo")).getString("id"))
    }
    @Test fun locksAndEditorConditionalSave() {
        val p = dir.resolve("a"); Files.write(p, "old".toByteArray())
        val v = version(p)
        assertEquals("", engine.tryAcquire("busy"))
        outcome(JSONObject(engine.saveText("", p.toString(), "new", v)), "rejected")
        engine.release("not-owner")
        assertEquals("", engine.tryAcquire("still-busy"))
        Thread { engine.release(token) }.apply { start(); join() }
        val saved = JSONObject(engine.saveText("", p.toString(), "new", v))
        outcome(saved, "committed")
        assertEquals(version(p), saved.getString("version"))
        outcome(JSONObject(engine.saveText("", p.toString(), "stale", v)), "rejected")
        token = engine.tryAcquire("again")
        assertNotEquals("", token)
        assertEquals("null", engine.peek(store.toString(), "undo"))
    }
    @Test fun saveRechecksAtPublication() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(1))
        engine.checkpoint = { if (it == "save-staged") Files.write(p, byteArrayOf(9)) }
        outcome(JSONObject(engine.saveText(token, p.toString(), "new", version(p))), "rejected")
        assertArrayEquals(byteArrayOf(9), Files.readAllBytes(p))
    }
    @Test fun snapshotBudgetRejectsBeforeJournalPublication() {
        val p = dir.resolve("large"); Files.write(p, ByteArray(1572865))
        try { observe(p); fail() } catch (_: IOException) { }
        val small = dir.resolve("small")
        outcome(execute(request("write", small, bytes = ByteArray(1572865))), "rejected")
        assertFalse(Files.exists(small))
    }
    @Test fun implicitParentsPublishAndUndoAsOneConditionalTree() {
        val p = dir.resolve("new/deep/file")
        val req = request("write", p)
        val r = execute(req)
        outcome(r, "committed")
        assertArrayEquals(byteArrayOf(1, 2, 3), Files.readAllBytes(p))
        assertEquals(p.toString(), r.getJSONArray("changes").getJSONObject(0).getString("path"))
        outcome(history("undo", req.getString("transactionId")), "committed")
        assertFalse(Files.exists(dir.resolve("new")))
        outcome(history("redo", req.getString("transactionId")), "committed")
        Files.write(p.parent.resolve("external"), byteArrayOf(9))
        outcome(history("undo", req.getString("transactionId")), "rejected")
        assertTrue(Files.exists(p.parent.resolve("external")))
    }
    @Test fun implicitParentPreparedCrashLeavesNoDirectories() {
        val p = dir.resolve("new/deep/file")
        val req = request("write", p)
        engine.checkpoint = { if (it == "prepared") throw Crash() }
        try { execute(req); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertTrue(recover().getBoolean("recovered"))
        assertFalse(Files.exists(dir.resolve("new")))
    }
    @Test fun removedCheckpointRecoveryRestoresRenameSource() {
        val p = dir.resolve("source"); Files.createDirectory(p)
        Files.write(p.resolve("binary"), byteArrayOf(-1, 0, 2))
        val target = dir.resolve("destination")
        val req = request("rename", p, target)
        engine.checkpoint = { if (it == "removed:0") throw Crash() }
        try { execute(req); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertTrue(recover().getBoolean("recovered"))
        assertTrue(recover().getBoolean("recovered"))
        assertArrayEquals(byteArrayOf(-1, 0, 2), Files.readAllBytes(p.resolve("binary")))
        assertFalse(Files.exists(target))
    }
    @Test fun symlinkFinalAndParentsAreRejected() {
        val actual = dir.resolve("actual"); Files.createDirectory(actual)
        Files.write(actual.resolve("a"), byteArrayOf(1))
        val link = dir.resolve("link")
        try { Files.createSymbolicLink(link, actual) } catch (e: Exception) { assumeNoException(e) }
        for (p in listOf(link, link.resolve("a"), link.resolve("missing"))) {
            try { observe(p); fail("Accepted symbolic link: $p") } catch (_: IOException) { }
        }
    }
    @Test fun atomicMoveFailureNeverFallsBackToDestructivePublication() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(9))
        val req = request("write", p)
        engine.checkpoint = { if (it == "staged:0") throw java.nio.file.AtomicMoveNotSupportedException("stage", "target", "injected") }
        outcome(execute(req), "rolled_back")
        assertArrayEquals(byteArrayOf(9), Files.readAllBytes(p))
    }
    private fun journalFiles() = Files.newDirectoryStream(store, "tx-*.json").use { it.toList() }
    @Test fun corruptRecoveryPathsAndFingerprintsNeverTouchVictims() {
        val p = dir.resolve("a"); val victim = dir.resolve("victim")
        Files.write(victim, byteArrayOf(77))
        val req = request("write", p)
        engine.checkpoint = { if (it == "prepared") throw Crash() }
        try { execute(req); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        val file = journalFiles().single()
        val original = String(Files.readAllBytes(file))
        val invalid = JSONObject(original)
        invalid.getJSONArray("steps").getJSONObject(0).put("backup", victim.toString())
        Files.write(file, invalid.toString().toByteArray())
        assertFalse(recover().getBoolean("recovered"))
        assertArrayEquals(byteArrayOf(77), Files.readAllBytes(victim))
        assertFalse(Files.exists(p))
        val badHash = JSONObject(original)
        badHash.getJSONArray("steps").getJSONObject(0).getJSONObject("after").put("version", "0".repeat(64))
        Files.write(file, badHash.toString().toByteArray())
        assertFalse(recover().getBoolean("recovered"))
        Files.write(file, original.toByteArray())
        assertTrue(recover().getBoolean("recovered"))
    }
    @Test fun terminalSnapshotsAreCollectedButResultsRemainAndAppliedIsBounded() {
        val p = dir.resolve("a")
        var first: JSONObject? = null
        repeat(12) { n ->
            val req = request("write", p, bytes = ByteArray(32768) { n.toByte() })
            if (n == 0) first = req
            outcome(execute(req), "committed")
        }
        val records = journalFiles().map { JSONObject(String(Files.readAllBytes(it))) }
        assertEquals(10, records.count { !it.optBoolean("tombstone") })
        assertEquals(0, JSONObject(String(Files.readAllBytes(store.resolve("history.json")))).getJSONArray("applied").length())
        outcome(JSONObject(engine.getResult(store.toString(), first!!.getString("transactionId"))), "committed")
        outcome(execute(first!!), "committed")
        assertArrayEquals(ByteArray(32768) { 11 }, Files.readAllBytes(p))
    }
    @Test fun recoveryReportsOnlyNewlyRecoveredTransactions() {
        outcome(execute(request("write", dir.resolve("normal"))), "committed")
        assertEquals(0, recover().getJSONArray("results").length())
        val req = request("write", dir.resolve("crash"))
        engine.checkpoint = { if (it == "committed") throw Crash() }
        try { execute(req); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertEquals(1, recover().getJSONArray("results").length())
        assertEquals(0, recover().getJSONArray("results").length())
    }
    @Test fun saveNeverBindsBufferToThirdPartyVersion() {
        val p = dir.resolve("a"); Files.write(p, byteArrayOf(1))
        engine.checkpoint = { if (it == "save-published") Files.write(p, byteArrayOf(9)) }
        val r = JSONObject(engine.saveText(token, p.toString(), "mine", version(p)))
        outcome(r, "partial")
        assertFalse(r.has("version"))
        assertEquals(version(p), r.getString("observedVersion"))
        assertEquals("CONFLICT", r.getJSONObject("error").getString("code"))
    }
    @Test fun missingUnderRegularFileIsNotReportedAsMissing() {
        val p = dir.resolve("file"); Files.write(p, byteArrayOf(1))
        try { observe(p.resolve("child")); fail() } catch (_: IOException) { }
    }
    @Test fun editorBusyReturnsWithoutWaitingForTransactionMonitor() {
        val entered = java.util.concurrent.CountDownLatch(1)
        val exit = java.util.concurrent.CountDownLatch(1)
        val p = dir.resolve("a"); val req = request("write", p)
        val expected = version(p)
        engine.checkpoint = { if (it == "prepared") { entered.countDown(); exit.await() } }
        val worker = Thread { execute(req) }
        worker.start()
        assertTrue(entered.await(5, java.util.concurrent.TimeUnit.SECONDS))
        val pool = java.util.concurrent.Executors.newSingleThreadExecutor()
        try {
            val saved = pool.submit<String> { engine.saveText("", p.toString(), "editor", expected) }
            outcome(JSONObject(saved.get(1, java.util.concurrent.TimeUnit.SECONDS)), "rejected")
        } finally { exit.countDown(); worker.join(); pool.shutdownNow() }
    }
    @Test fun pendingProjectionRecoveryUsesSequenceRatherThanHashedFilename() {
        val p = dir.resolve("a")
        fun hashed(value: String) = java.security.MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }
        val firstId = "sequence-first"
        var secondId = "sequence-second"
        while (hashed(secondId) > hashed(firstId)) secondId += "x"
        val first = request("write", p, bytes = byteArrayOf(1), tx = firstId)
        outcome(execute(first), "committed")
        val second = request("write", p, bytes = byteArrayOf(2), tx = secondId)
        outcome(execute(second), "committed")
        // Simulate loss of the replayable projection, retaining ordered commit journals.
        journalFiles().forEach { file ->
            val j = JSONObject(String(Files.readAllBytes(file))); j.remove("result")
            Files.write(file, j.toString().toByteArray())
        }
        Files.write(store.resolve("history.json"), "{\"undo\":[],\"redo\":[],\"applied\":[]}".toByteArray())
        val report = recover()
        assertTrue(report.toString(), report.getBoolean("recovered"))
        assertEquals(firstId, report.getJSONArray("results").getJSONObject(0).getString("transactionId"))
        assertEquals(secondId, JSONObject(engine.peek(store.toString(), "undo")).getString("id"))
    }
    @Test fun listResultsReplaysCompactedHistoryResultsInSequenceAndFiltersScope() {
        val p = dir.resolve("a")
        val req = request("write", p)
        outcome(execute(req), "committed")
        val undone = history("undo", req.getString("transactionId"))
        outcome(undone, "committed")
        val other = request("write", dir.resolve("other")).put("scopeId", "other-scope")
        outcome(execute(other), "committed")
        val listed = JSONArray(engine.listResults(store.toString(), "scope"))
        assertEquals(2, listed.length())
        assertEquals(req.getString("transactionId"), listed.getJSONObject(0).getString("transactionId"))
        assertEquals(undone.getString("transactionId"), listed.getJSONObject(1).getString("transactionId"))
        assertEquals(1, JSONArray(engine.listResults(store.toString(), "other-scope")).length())
        assertEquals(0, JSONArray(engine.listResults(store.toString(), "unknown-scope")).length())
        assertTrue(recover().getBoolean("recovered"))
        assertEquals(listed.toString(), engine.listResults(store.toString(), "scope"))
    }
    private fun oldFile(p: Path, data: String, encoding: String? = null) = JSONObject().put("path", p.toString()).put("kind", "file").put("content", data).put("fingerprint", "untrusted-weak").apply { if (encoding != null) put("encoding", encoding) }
    private fun oldRecord(p: Path, before: JSONObject, after: JSONObject, name: String = "create_file") = JSONObject()
        .put("id", "old-id").put("name", name).put("scope", dir.toString()).put("args", JSONObject().put("path", p.toString()))
        .put("before", JSONArray().put(before)).put("after", JSONArray().put(after))
    private fun legacy(record: JSONObject, direction: String = "undo") = JSONObject().put("undo", JSONArray()).put("redo", JSONArray()).put(direction, JSONArray().put(record)).toString()
    private fun imported(raw: String) = JSONObject(engine.importLegacy(token, store.toString(), dir.toString(), raw))
    @Test fun legacyUtf8AndBinaryUndoRedoRoundtripIsIdempotent() {
        val p = dir.resolve("legacy")
        val binary = byteArrayOf(0, -1, -128)
        Files.write(p, binary)
        val raw = legacy(oldRecord(p, oldFile(p, "旧内容"), oldFile(p, Base64.getEncoder().encodeToString(binary), "base64")))
        val r = imported(raw)
        assertTrue(r.toString(), r.getBoolean("imported"))
        assertEquals(1, r.getInt("migratedCount")); assertEquals(1, r.getJSONArray("warnings").length())
        assertArrayEquals(binary, Files.readAllBytes(p))
        assertTrue(imported(raw).getBoolean("imported"))
        val tx = JSONObject(engine.peek(store.toString(), "undo")).getString("id")
        outcome(JSONObject(engine.history(token, store.toString(), dir.toString(), "undo", tx)), "committed")
        assertEquals("旧内容", String(Files.readAllBytes(p), Charsets.UTF_8))
        outcome(JSONObject(engine.history(token, store.toString(), dir.toString(), "redo", tx)), "committed")
        assertArrayEquals(binary, Files.readAllBytes(p))
    }
    @Test fun legacyDirectoryRedoRebuildsMissingManifestParents() {
        val p = dir.resolve("tree")
        val missing = JSONObject().put("path", p.toString()).put("kind", "missing")
        val tree = JSONObject().put("path", p.toString()).put("kind", "dir").put("dirs", JSONArray().put(p.resolve("empty").toString()))
            .put("files", JSONArray().put(oldFile(p.resolve("nested/a"), "AAH/", "base64")))
        val raw = legacy(oldRecord(p, missing, tree, "create_directory"), "redo")
        assertTrue(imported(raw).getBoolean("imported"))
        assertFalse(Files.exists(p))
        val tx = JSONObject(engine.peek(store.toString(), "redo")).getString("id")
        outcome(JSONObject(engine.history(token, store.toString(), dir.toString(), "redo", tx)), "committed")
        assertArrayEquals(byteArrayOf(0, 1, -1), Files.readAllBytes(p.resolve("nested/a")))
        assertTrue(Files.isDirectory(p.resolve("empty")))
    }
    @Test fun legacyInvalidSourcesRemainUntouchedAndNativeHistoryWins() {
        val p = dir.resolve("a")
        val sourceFile = dir.resolve("legacy.json")
        val raw = legacy(oldRecord(p, oldFile(p, "old"), oldFile(p, "%%%", "base64")))
        Files.write(sourceFile, raw.toByteArray())
        assertFalse(imported(raw).getBoolean("imported"))
        assertEquals(raw, String(Files.readAllBytes(sourceFile)))
        assertFalse(Files.exists(p))
        val evil = oldRecord(p, oldFile(p, "old"), oldFile(dir.parent.resolve("outside"), "evil"))
        assertFalse(imported(legacy(evil)).getBoolean("imported"))
        val good = legacy(oldRecord(p, oldFile(p, "old"), oldFile(p, "new")))
        outcome(execute(request("write", p)), "committed")
        val head = engine.peek(store.toString(), "undo")
        val rejected = imported(good)
        assertEquals("HISTORY_EXISTS", rejected.getJSONObject("error").getString("code"))
        assertEquals(head, engine.peek(store.toString(), "undo"))
    }
    @Test fun legacyProjectionCrashCanCompleteMarkerWithoutDuplicatingHistory() {
        val p = dir.resolve("a"); Files.write(p, "new".toByteArray())
        val raw = legacy(oldRecord(p, oldFile(p, "old"), oldFile(p, "new")))
        engine.checkpoint = { if (it == "legacy-projection") throw Crash() }
        try { imported(raw); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertTrue(imported(raw).getBoolean("imported"))
        assertEquals(1, JSONArray(engine.listResults(store.toString(), dir.toString())).length())
        assertEquals("new", String(Files.readAllBytes(p)))
    }
    @Test fun legacyScopeMismatchAndPreProjectionCrashAreSafe() {
        val p = dir.resolve("a"); Files.write(p, "new".toByteArray())
        val record = oldRecord(p, oldFile(p, "old"), oldFile(p, "new"))
        val wrong = JSONObject(record.toString()).put("scope", dir.resolve("sub").toString())
        assertEquals("LEGACY_SCOPE", imported(legacy(wrong)).getJSONObject("error").getString("code"))
        val raw = legacy(record)
        engine.checkpoint = { if (it == "legacy-journals") throw Crash() }
        try { imported(raw); fail() } catch (_: Crash) { }
        engine.checkpoint = null
        assertEquals("null", engine.peek(store.toString(), "undo"))
        assertTrue(imported(raw).getBoolean("imported"))
        assertEquals(1, JSONArray(engine.listResults(store.toString(), dir.toString())).length())
        assertEquals("new", String(Files.readAllBytes(p)))
    }
}

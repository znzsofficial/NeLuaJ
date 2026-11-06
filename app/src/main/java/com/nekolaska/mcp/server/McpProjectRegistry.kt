package com.nekolaska.mcp.server

import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.util.UUID

/** One explicitly authorized project per activation. Navigation is not authorization. */
class McpProjectRegistry(val projectRoot: String, val writable: Boolean) {
    val handle: String = UUID.randomUUID().toString()
    private val root: Path
    @Volatile private var active = true

    init {
        val supplied = Paths.get(projectRoot)
        require(supplied.isAbsolute && supplied.none { it.toString() == ".." }) { "Absolute project root required" }
        var checked = supplied.normalize()
        if (System.getProperty("java.vm.name", "").contains("Dalvik", true)) {
            val alias = listOf(Paths.get("/sdcard"), Paths.get("/storage/emulated/0"))
                .firstOrNull { checked.startsWith(it) }
            if (alias != null) checked = alias.toRealPath().resolve(alias.relativize(checked))
        }
        var current = checked.root
        for (part in checked) {
            current = current.resolve(part)
            require(!Files.isSymbolicLink(current)) { "Symbolic links are not authorized" }
        }
        require(checked.parent != null && Files.isDirectory(checked, NOFOLLOW_LINKS)) { "Project directory required" }
        root = checked
    }

    fun isActive() = active
    fun revoke() { active = false }

    fun authorize(value: String, write: Boolean = false) {
        check(active && value == handle) { "Invalid or revoked projectHandle" }
        check(!write || writable) { "Project is read-only" }
    }

    fun resolve(relative: String, allowRoot: Boolean = false): Path {
        check(active) { "Project authorization revoked" }
        require(relative.length <= 4096 && !relative.contains('\\') && !relative.contains('\u0000')) { "Invalid relative path" }
        val input = Paths.get(relative)
        require(!input.isAbsolute && input.none { it.toString() == ".." || it.toString().contains(':') }) { "Project-relative path required" }
        val resolved = root.resolve(input).normalize()
        require(resolved.startsWith(root) && (allowRoot || resolved != root)) { "Path outside project or project root" }
        // Recheck the root too: replacing the authorized directory with a link does not grant its target.
        var current = root.root
        for (part in resolved) {
            current = current.resolve(part)
            require(!Files.isSymbolicLink(current)) { "Symbolic links are not authorized" }
        }
        return resolved
    }

    fun relative(path: Path): String = root.relativize(path).joinToString("/")
}

@file:Suppress("HasPlatformType", "NOTHING_TO_INLINE")

package com.nekolaska.ktx

import org.luaj.Globals
import org.luaj.LuaString
import org.luaj.lib.BaseLib
import org.luaj.lib.DebugLib
import org.luaj.lib.PackageLib
import org.luaj.lib.ResourceFinder
import org.luaj.lib.StringLib
import org.luaj.lib.jse.LuajavaLib
import java.io.InputStream
import java.io.PrintStream

/**
 * Named adapters for public but obfuscated fields in the bundled legacy LuaJ runtime.
 * Keep direct field access in this file so Kotlin callers remain readable and upgrades are local.
 */
inline val LuaString.bytes: ByteArray get() = c
inline val LuaString.offset: Int get() = d
inline val LuaString.byteLength: Int get() = e

@Deprecated("Use bytes", ReplaceWith("bytes"))
inline val LuaString.m_bytes get() = bytes

@Deprecated("Use offset", ReplaceWith("offset"))
inline val LuaString.m_offset get() = offset

@Deprecated("Use byteLength", ReplaceWith("byteLength"))
inline val LuaString.m_length get() = byteLength

inline var Globals.resourceFinder: ResourceFinder
    get() = requireNotNull(m) { "Globals.resourceFinder is not installed" }
    set(value) {
        m = value
    }

@Deprecated("Use resourceFinder", ReplaceWith("resourceFinder"))
inline var Globals.finder: ResourceFinder
    get() = resourceFinder
    set(value) {
        resourceFinder = value
    }

inline var Globals.standardInput: InputStream?
    get() = j
    set(value) {
        j = value
    }

inline var Globals.standardOutput: PrintStream?
    get() = k
    set(value) {
        k = value
    }

inline var Globals.standardError: PrintStream?
    get() = l
    set(value) {
        l = value
    }

inline val Globals.packageLib: PackageLib get() = requireNotNull(p) { "PackageLib is not installed" }
inline val Globals.debugLib: DebugLib get() = requireNotNull(q) { "DebugLib is not installed" }
inline val Globals.baseLib: BaseLib get() = requireNotNull(o) { "BaseLib is not installed" }
inline val Globals.stringLib: StringLib get() = requireNotNull(r) { "StringLib is not installed" }
inline val Globals.luajavaLib: LuajavaLib get() = requireNotNull(s) { "LuaJava is not installed" }

inline val PackageLib.requireFunction: PackageLib.require get() = requireNotNull(y) { "PackageLib is not installed" }
inline val BaseLib.tostring: BaseLib.tostring get() = requireNotNull(e) { "BaseLib is not installed" }
inline val StringLib.format: StringLib.format get() = requireNotNull(f) { "StringLib is not installed" }

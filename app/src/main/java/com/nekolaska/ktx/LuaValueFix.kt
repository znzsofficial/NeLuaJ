@file:Suppress("HasPlatformType")

package com.nekolaska.ktx

import org.luaj.Globals
import org.luaj.LuaString
import org.luaj.lib.BaseLib
import org.luaj.lib.StringLib

inline val LuaString.m_bytes get() = c
inline val LuaString.m_offset get() = d
inline val LuaString.m_length get() = e
inline val Globals.finder get() = m
inline val Globals.baseLib get() = o
inline val Globals.stringLib get() = r
inline val BaseLib.tostring get() = e
inline val StringLib.format get() = f
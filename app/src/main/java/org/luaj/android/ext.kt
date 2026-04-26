package org.luaj.android

import com.nekolaska.ktx.m_bytes
import com.nekolaska.ktx.m_length
import com.nekolaska.ktx.m_offset
import org.luaj.LuaError
import org.luaj.LuaString
import org.luaj.LuaTable
import org.luaj.LuaValue
import org.luaj.Varargs
import org.luaj.lib.TwoArgFunction
import org.luaj.lib.VarArgFunction
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

class ext : TwoArgFunction() {
    override fun call(modname: LuaValue?, env: LuaValue): LuaValue {
        val ext = LuaTable().apply {
            set("pack", Pack())
            set("unpack", Unpack())
            set("packsize", PackSize())
        }
        env.set("ext", ext)
        if (!env.get("package").isnil()) env.get("package").get("loaded").set("ext", ext)
        return NIL
    }

    private enum class Kind {
        INT, UINT, FLOAT, DOUBLE, CHAR, STRING, ZSTRING, PADDING, PADDING_ALIGN, NOP
    }

    private data class Option(val kind: Kind, val size: Int, val align: Int)

    private class Header {
        var isLittle = ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN
        var maxAlign = 1
    }

    private class Parser(private val format: String) {
        private var index = 0
        private val header = Header()

        fun hasNext(): Boolean = index < format.length

        fun next(totalsize: Int): Pair<Option, Int> {
            val option = readOption()
            var align = option.align
            if (option.kind == Kind.PADDING_ALIGN) {
                if (index >= format.length) throw LuaError("invalid next option for option 'X'")
                align = readOption().align
                if (align <= 0) throw LuaError("invalid next option for option 'X'")
            }
            val ntoalign = if (align <= 1 || option.kind == Kind.CHAR) {
                0
            } else {
                val limitedAlign = min(align, header.maxAlign)
                if (!limitedAlign.isPowerOfTwo()) throw LuaError("format asks for alignment not power of 2")
                (limitedAlign - (totalsize and (limitedAlign - 1))) and (limitedAlign - 1)
            }
            return option to ntoalign
        }

        private fun readOption(): Option {
            val opt = format[index++]
            return when (opt) {
                'b' -> Option(Kind.INT, 1, 1)
                'B' -> Option(Kind.UINT, 1, 1)
                'h' -> Option(Kind.INT, 2, 2)
                'H' -> Option(Kind.UINT, 2, 2)
                'l' -> Option(Kind.INT, 8, 8)
                'L' -> Option(Kind.UINT, 8, 8)
                'j' -> Option(Kind.INT, 8, 8)
                'J' -> Option(Kind.UINT, 8, 8)
                'T' -> Option(Kind.UINT, 8, 8)
                'f' -> Option(Kind.FLOAT, 4, 4)
                'n', 'd' -> Option(Kind.DOUBLE, 8, 8)
                'i' -> Option(Kind.INT, readLimitedNumber(4), readLimitedNumberLast)
                'I' -> Option(Kind.UINT, readLimitedNumber(4), readLimitedNumberLast)
                's' -> Option(Kind.STRING, readLimitedNumber(8), readLimitedNumberLast)
                'c' -> Option(Kind.CHAR, readNumber(-1).also {
                    if (it < 0) throw LuaError("missing size for format option 'c'")
                }, 1)
                'z' -> Option(Kind.ZSTRING, 0, 1)
                'x' -> Option(Kind.PADDING, 1, 1)
                'X' -> Option(Kind.PADDING_ALIGN, 0, 0)
                ' ' -> Option(Kind.NOP, 0, 0)
                '<' -> { header.isLittle = true; Option(Kind.NOP, 0, 0) }
                '>' -> { header.isLittle = false; Option(Kind.NOP, 0, 0) }
                '=' -> { header.isLittle = ByteOrder.nativeOrder() == ByteOrder.LITTLE_ENDIAN; Option(Kind.NOP, 0, 0) }
                '!' -> {
                    val align = readLimitedNumber(8)
                    header.maxAlign = align
                    Option(Kind.NOP, 0, 0)
                }
                else -> throw LuaError("invalid format option '$opt'")
            }
        }

        fun order(): ByteOrder = if (header.isLittle) ByteOrder.LITTLE_ENDIAN else ByteOrder.BIG_ENDIAN

        private var readLimitedNumberLast = 0

        private fun readLimitedNumber(defaultValue: Int): Int {
            val n = readNumber(defaultValue)
            if (n !in 1..16) throw LuaError("integral size ($n) out of limits [1,16]")
            readLimitedNumberLast = n
            return n
        }

        private fun readNumber(defaultValue: Int): Int {
            if (index >= format.length || !format[index].isDigit()) return defaultValue
            var n = 0L
            while (index < format.length && format[index].isDigit()) {
                n = n * 10 + (format[index++] - '0')
                if (n > Int.MAX_VALUE) throw LuaError("format size too large")
            }
            return n.toInt()
        }
    }

    private class Pack : VarArgFunction() {
        override fun invoke(args: Varargs): LuaValue {
            val parser = Parser(args.checkjstring(1))
            val out = ByteArrayOutputStream()
            var arg = 1
            while (parser.hasNext()) {
                val (option, padding) = parser.next(out.size())
                repeat(padding) { out.write(0) }
                when (option.kind) {
                    Kind.INT -> {
                        arg++
                        val n = args.checklong(arg)
                        checkSigned(n, option.size, arg)
                        writeInteger(out, n, option.size, parser.order())
                    }
                    Kind.UINT -> {
                        arg++
                        val n = args.checklong(arg)
                        checkUnsigned(n, option.size, arg)
                        writeInteger(out, n, option.size, parser.order())
                    }
                    Kind.FLOAT -> {
                        arg++
                        val bytes = ByteBuffer.allocate(4).order(parser.order()).putFloat(args.checkdouble(arg).toFloat()).array()
                        out.write(bytes)
                    }
                    Kind.DOUBLE -> {
                        arg++
                        val bytes = ByteBuffer.allocate(8).order(parser.order()).putDouble(args.checkdouble(arg)).array()
                        out.write(bytes)
                    }
                    Kind.CHAR -> {
                        arg++
                        val s = args.checkstring(arg).toBytes()
                        if (s.size > option.size) throw LuaError("bad argument #$arg (string longer than given size)")
                        out.write(s)
                        repeat(option.size - s.size) { out.write(0) }
                    }
                    Kind.STRING -> {
                        arg++
                        val s = args.checkstring(arg).toBytes()
                        checkUnsigned(s.size.toLong(), option.size, arg, "string length does not fit in given size")
                        writeInteger(out, s.size.toLong(), option.size, parser.order())
                        out.write(s)
                    }
                    Kind.ZSTRING -> {
                        arg++
                        val s = args.checkstring(arg).toBytes()
                        if (s.any { it.toInt() == 0 }) throw LuaError("bad argument #$arg (string contains zeros)")
                        out.write(s)
                        out.write(0)
                    }
                    Kind.PADDING -> out.write(0)
                    Kind.PADDING_ALIGN, Kind.NOP -> Unit
                }
            }
            return LuaString.valueUsing(out.toByteArray())
        }
    }

    private class PackSize : VarArgFunction() {
        override fun invoke(args: Varargs): LuaValue {
            val parser = Parser(args.checkjstring(1))
            var totalsize = 0
            while (parser.hasNext()) {
                val (option, padding) = parser.next(totalsize)
                if (option.kind == Kind.STRING || option.kind == Kind.ZSTRING) {
                    throw LuaError("bad argument #1 (variable-length format)")
                }
                totalsize += padding + option.size
            }
            return valueOf(totalsize)
        }
    }

    private class Unpack : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs {
            val parser = Parser(args.checkjstring(1))
            val data = args.checkstring(2).toBytes()
            var pos = posrelat(args.optlong(3, 1), data.size) - 1
            if (pos !in 0..data.size) throw LuaError("bad argument #3 (initial position out of string)")
            val result = ArrayList<LuaValue>()
            while (parser.hasNext()) {
                val (option, padding) = parser.next(pos)
                if (padding + option.size > data.size - pos) throw LuaError("bad argument #2 (data string too short)")
                pos += padding
                when (option.kind) {
                    Kind.INT -> result.add(valueOf(readInteger(data, pos, option.size, parser.order(), true)))
                    Kind.UINT -> result.add(valueOf(readInteger(data, pos, option.size, parser.order(), false)))
                    Kind.FLOAT -> result.add(valueOf(ByteBuffer.wrap(data, pos, 4).order(parser.order()).float.toDouble()))
                    Kind.DOUBLE -> result.add(valueOf(ByteBuffer.wrap(data, pos, 8).order(parser.order()).double))
                    Kind.CHAR -> result.add(LuaString.valueUsing(data.copyOfRange(pos, pos + option.size)))
                    Kind.STRING -> {
                        val len = readInteger(data, pos, option.size, parser.order(), false)
                        if (len < 0 || len > data.size - pos - option.size) throw LuaError("bad argument #2 (data string too short)")
                        val start = pos + option.size
                        result.add(LuaString.valueUsing(data.copyOfRange(start, start + len.toInt())))
                        pos += len.toInt()
                    }
                    Kind.ZSTRING -> {
                        val end = data.indexOfZero(pos)
                        if (end < 0) throw LuaError("bad argument #2 (unfinished string for format 'z')")
                        result.add(LuaString.valueUsing(data.copyOfRange(pos, end)))
                        pos = end + 1
                    }
                    Kind.PADDING, Kind.PADDING_ALIGN, Kind.NOP -> Unit
                }
                pos += option.size
            }
            result.add(valueOf(pos + 1))
            return varargsOf(result.toTypedArray())
        }
    }

    companion object {
        private fun Int.isPowerOfTwo(): Boolean = this > 0 && (this and (this - 1)) == 0

        private fun LuaString.toBytes(): ByteArray = m_bytes.copyOfRange(m_offset, m_offset + m_length)

        private fun ByteArray.indexOfZero(start: Int): Int {
            for (i in start until size) if (this[i].toInt() == 0) return i
            return -1
        }

        private fun posrelat(pos: Long, len: Int): Int {
            return when {
                pos > 0 -> pos.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                pos == 0L -> 1
                pos < -len.toLong() -> 1
                else -> (len + pos + 1).toInt()
            }
        }

        private fun checkSigned(value: Long, size: Int, arg: Int) {
            if (size >= 8) return
            val limit = 1L shl (size * 8 - 1)
            if (value < -limit || value >= limit) throw LuaError("bad argument #$arg (integer overflow)")
        }

        private fun checkUnsigned(value: Long, size: Int, arg: Int, message: String = "unsigned overflow") {
            if (size >= 8) return
            val limit = 1L shl (size * 8)
            if (value < 0 || value >= limit) throw LuaError("bad argument #$arg ($message)")
        }

        private fun writeInteger(out: ByteArrayOutputStream, value: Long, size: Int, order: ByteOrder) {
            if (order == ByteOrder.LITTLE_ENDIAN) {
                for (i in 0 until size) out.write(((value ushr (i * 8)) and 0xff).toInt())
            } else {
                for (i in size - 1 downTo 0) out.write(((value ushr (i * 8)) and 0xff).toInt())
            }
        }

        private fun readInteger(data: ByteArray, pos: Int, size: Int, order: ByteOrder, signed: Boolean): Long {
            val limit = min(size, 8)
            var result = 0L
            if (order == ByteOrder.LITTLE_ENDIAN) {
                for (i in limit - 1 downTo 0) result = (result shl 8) or (data[pos + i].toLong() and 0xff)
            } else {
                for (i in 0 until limit) result = (result shl 8) or (data[pos + i].toLong() and 0xff)
            }
            if (size < 8 && signed) {
                val shift = 64 - size * 8
                result = (result shl shift) shr shift
            } else if (size > 8) {
                val signByte = if (signed && result < 0) 0xff else 0x00
                for (i in 8 until size) {
                    val b = data[pos + if (order == ByteOrder.LITTLE_ENDIAN) i else size - 1 - i].toInt() and 0xff
                    if (b != signByte) throw LuaError("$size-byte integer does not fit into Lua Integer")
                }
            }
            return result
        }
    }
}

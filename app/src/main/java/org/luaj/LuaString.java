//
// Decompiled by Jadx - 598ms
//
package org.luaj;

import java.io.ByteArrayInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import org.luaj.lib.MathLib;

public class LuaString extends LuaValue {
    public static LuaValue b;
    public final byte[] c;
    public final int d;
    public final int e;
    private int f;
    private char[] g;
    private String h;
    private boolean i;

    public static final class RecentShortStrings {
        private static final LuaString[] a = new LuaString[128];

        private RecentShortStrings() {
        }
    }

    private LuaString(byte[] bArr, int i, int i2) {
        this.c = bArr;
        this.d = i;
        this.e = i2;
    }

    private double a(int i, int i2, int i3) {
        boolean z = this.c[i2] == 45;
        if (z) {
            i2++;
        }
        long j = 0;
        while (i2 < i3) {
            byte[] bArr = this.c;
            byte b2 = bArr[i2];
            byte b3 = 48;
            if (i > 10 && (bArr[i2] < 48 || bArr[i2] > 57)) {
                byte[] bArr2 = this.c;
                b3 = (bArr2[i2] < 65 || bArr2[i2] > 90) ? (byte) 87 : (byte) 55;
            }
            int i4 = b2 - b3;
            if (i4 < 0 || i4 >= i) {
                return Double.NaN;
            }
            j = (j * i) + i4;
            if (j < 0) {
                return Double.NaN;
            }
            i2++;
        }
        return z ? -j : j;
    }

    static int a(int i, int i2) {
        return i >= 0 ? i : i2 + i + 1;
    }

    private Long a(int i) {
        int start = this.d;
        int end = this.e + start;
        while (start < end && this.c[start] == 32) {
            start++;
        }
        while (start < end && this.c[end - 1] == 32) {
            end--;
        }
        if (start >= end) {
            return null;
        }
        boolean negative = this.c[start] == 45;
        if (negative) {
            start++;
        }
        if (start >= end) {
            return null;
        }
        long value = 0;
        while (start < end) {
            int character = this.c[start++];
            int digit = character >= 48 && character <= 57
                    ? character - 48
                    : character >= 65 && character <= 90
                        ? character - 55
                        : character >= 97 && character <= 122 ? character - 87 : -1;
            if (digit < 0 || digit >= i) {
                return null;
            }
            value = (value * i) + digit;
        }
        return negative ? -value : value;
    }

    private boolean a(byte[] bArr, int i, int i2) {
        return this.e == i2 && equals(this.c, this.d, bArr, i, i2);
    }

    private double b(int i, int i2) {
        int i3 = i + 64;
        if (i2 > i3) {
            i2 = i3;
        }
        for (int i4 = i; i4 < i2; i4++) {
            byte b2 = this.c[i4];
            if (b2 != 43 && b2 != 69 && b2 != 101 && b2 != 45 && b2 != 46) {
                switch (b2) {
                    case 48:
                    case 49:
                    case 50:
                    case 51:
                    case 52:
                    case 53:
                    case 54:
                    case 55:
                    case 56:
                    case 57:
                        break;
                    default:
                        return Double.NaN;
                }
            }
        }
        char[] cArr = new char[i2 - i];
        for (int i5 = i; i5 < i2; i5++) {
            cArr[i5 - i] = (char) this.c[i5];
        }
        try {
            return Double.parseDouble(new String(cArr));
        } catch (Exception unused) {
            return Double.NaN;
        }
    }

    private static LuaString b(byte[] bArr, int i, int i2) {
        byte[] bArr2 = new byte[i2];
        System.arraycopy(bArr, i, bArr2, 0, i2);
        return new LuaString(bArr2, 0, i2);
    }

    private double d() {
        double scannumber = scannumber();
        if (Double.isNaN(scannumber)) {
            a();
        }
        return scannumber;
    }

    public static String decodeAsUtf8(byte[] bArr, int i, int i2) {
        return new String(bArr, i, i2);
    }

    private Long e() {
        int start = this.d;
        int end = this.e + start;
        while (start < end && this.c[start] == 32) start++;
        while (start < end && this.c[end - 1] == 32) end--;
        if (start >= end) return null;

        int base = 10;
        if (end - start > 2 && this.c[start] == 48 &&
                (this.c[start + 1] == 120 || this.c[start + 1] == 88)) {
            base = 16;
            start += 2;
        }
        boolean negative = this.c[start] == 45;
        if (negative) start++;
        if (start >= end) return null;

        long value = 0;
        while (start < end) {
            int character = this.c[start++];
            int digit = character >= 48 && character <= 57 ? character - 48 :
                character >= 65 && character <= 90 ? character - 55 :
                    character >= 97 && character <= 122 ? character - 87 : -1;
            if (digit < 0 || digit >= base) return null;
            value = value * base + digit;
        }
        return negative ? -value : value;
    }

    public static int encodeToUtf8(char[] cArr, int i, byte[] bArr, int i2) {
        int output = i2;
        for (int index = 0; index < i; index++) {
            char character = cArr[index];
            if (character < 128) {
                bArr[output++] = (byte) character;
            } else if (character < 2048) {
                bArr[output++] = (byte) ((character >> 6) | 192);
                bArr[output++] = (byte) ((character & 63) | 128);
            } else {
                bArr[output++] = (byte) ((character >> 12) | 224);
                bArr[output++] = (byte) (((character >> 6) & 63) | 128);
                bArr[output++] = (byte) ((character & 63) | 128);
            }
        }
        return output - i2;
    }

    public static boolean equals(LuaString luaString, int i, LuaString luaString2, int i2, int i3) {
        return equals(luaString.c, luaString.d + i, luaString2.c, luaString2.d + i2, i3);
    }

    public static boolean equals(byte[] bArr, int i, byte[] bArr2, int i2, int i3) {
        if (bArr.length < i + i3 || bArr2.length < i2 + i3) {
            return false;
        }
        while (true) {
            i3--;
            if (i3 < 0) {
                return true;
            }
            int i4 = i + 1;
            int i5 = i2 + 1;
            if (bArr[i] != bArr2[i2]) {
                return false;
            }
            i = i4;
            i2 = i5;
        }
    }

    public static int hashCode(byte[] bArr, int i, int i2) {
        int i3 = (i2 >> 5) + 1;
        int i4 = i2;
        while (i2 >= i3) {
            i4 ^= ((i4 << 5) + (i4 >> 2)) + (bArr[(i + i2) - 1] & 255);
            i2 -= i3;
        }
        return i4;
    }

    public static int lengthAsUtf8(char[] cArr) {
        int length = cArr.length;
        int i = length;
        while (true) {
            length--;
            if (length < 0) {
                return i;
            }
            char c = cArr[length];
            if (c >= 128) {
                i += c >= 2048 ? 2 : 1;
            }
        }
    }

    public static char[] toCharAsUtf8(byte[] bArr, int i, int i2) {
        return new String(bArr, i, i2).toCharArray();
    }

    public static LuaString valueOf(String str) {
        return valueUsing(str.getBytes());
    }

    public static LuaString valueOf(byte[] bArr) {
        return valueOf(bArr, 0, bArr.length);
    }

    public static LuaString valueOf(byte[] bArr, int i, int i2) {
        if (i2 > 32) {
            return b(bArr, i, i2);
        }
        int hashCode = hashCode(bArr, i, i2);
        int i3 = hashCode & 127;
        LuaString luaString = RecentShortStrings.a[i3];
        if (luaString != null && luaString.hashCode() == hashCode && luaString.a(bArr, i, i2)) {
            return luaString;
        }
        LuaString b2 = b(bArr, i, i2);
        RecentShortStrings.a[i3] = b2;
        return b2;
    }

    public static LuaString valueOf(char[] cArr) {
        return valueOf(cArr, 0, cArr.length);
    }

    public static LuaString valueOf(char[] cArr, int i, int i2) {
        byte[] bArr = new byte[i2];
        for (int i3 = 0; i3 < i2; i3++) {
            bArr[i3] = (byte) cArr[i3 + i];
        }
        return valueUsing(bArr, 0, i2);
    }

    public static LuaString valueUsing(byte[] bArr) {
        return valueUsing(bArr, 0, bArr.length);
    }

    public static LuaString valueUsing(byte[] bArr, int i, int i2) {
        if (bArr.length > 32) {
            return new LuaString(bArr, i, i2);
        }
        int hashCode = hashCode(bArr, i, i2);
        int i3 = hashCode & 127;
        LuaString luaString = RecentShortStrings.a[i3];
        if (luaString != null && luaString.hashCode() == hashCode && luaString.a(bArr, i, i2)) {
            return luaString;
        }
        LuaString luaString2 = new LuaString(bArr, i, i2);
        RecentShortStrings.a[i3] = luaString2;
        return luaString2;
    }

    public LuaValue add(double d) {
        return LuaValue.valueOf(d() + d);
    }

    public LuaValue add(int i) {
        return LuaValue.valueOf(d() + i);
    }

    public LuaValue add(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.ADD, luaValue) : luaValue.add(scannumber);
    }

    protected boolean c() {
        return true;
    }

    public LuaValue call(LuaValue luaValue) {
        if (!(luaValue instanceof LuaList) || !metatag(LuaValue.CALL).isnil()) {
            return super.call(luaValue);
        }
        int length = length();
        int a = a(luaValue.get(1).toint(), length);
        int a2 = a(luaValue.get(2).toint(), length);
        if (a < 1) {
            a = 1;
        }
        if (a2 > length) {
            a2 = length;
        }
        return a <= a2 ? substring(a - 1, a2) : LuaValue.EMPTYSTRING;
    }

    public int charAt(int i) {
        if (i < 0 || i >= this.e) {
            throw new IndexOutOfBoundsException();
        }
        return luaByte(i);
    }

    public double checkdouble() {
        double scannumber = scannumber();
        if (Double.isNaN(scannumber)) {
            a("number");
        }
        return scannumber;
    }

    public int checkint() {
        return (int) checkdouble();
    }

    public LuaInteger checkinteger() {
        return LuaValue.valueOf(checkint());
    }

    public String checkjstring() {
        return tojstring();
    }

    public long checklong() {
        return (long) checkdouble();
    }

    public LuaNumber checknumber() {
        return LuaValue.valueOf(checkdouble());
    }

    public LuaNumber checknumber(String str) {
        double scannumber = scannumber();
        if (!Double.isNaN(scannumber)) {
            return LuaValue.valueOf(scannumber);
        }
        LuaValue.error(str);
        throw null;
    }

    public LuaString checkstring() {
        return this;
    }

    public Buffer concat(Buffer buffer) {
        return buffer.concatTo(this);
    }

    public LuaValue concat(LuaValue luaValue) {
        return luaValue.concatTo(this);
    }

    public LuaValue concatTo(LuaNumber luaNumber) {
        return concatTo(luaNumber.strvalue());
    }

    public LuaValue concatTo(LuaString luaString) {
        int i = luaString.e;
        byte[] bArr = new byte[this.e + i];
        System.arraycopy(luaString.c, luaString.d, bArr, 0, i);
        System.arraycopy(this.c, this.d, bArr, luaString.e, this.e);
        return valueUsing(bArr, 0, bArr.length);
    }

    public LuaValue concatTo(LuaUtf8String luaUtf8String) {
        LuaString strvalue = luaUtf8String.strvalue();
        int i = strvalue.e;
        byte[] bArr = new byte[this.e + i];
        System.arraycopy(strvalue.c, strvalue.d, bArr, 0, i);
        System.arraycopy(this.c, this.d, bArr, strvalue.e, this.e);
        return valueUsing(bArr, 0, bArr.length);
    }

    public void copyInto(int i, byte[] bArr, int i2, int i3) {
        System.arraycopy(this.c, this.d + i, bArr, i2, i3);
    }

    public LuaValue div(double d) {
        return LuaDouble.ddiv(d(), d);
    }

    public LuaValue div(int i) {
        return LuaDouble.ddiv(d(), i);
    }

    public LuaValue div(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.DIV, luaValue) : luaValue.divInto(scannumber);
    }

    public LuaValue divInto(double d) {
        return LuaDouble.ddiv(d, d());
    }

    public LuaValue eq(LuaValue luaValue) {
        return luaValue.raweq(this) ? LuaValue.TRUE : LuaValue.FALSE;
    }

    public boolean eq_b(LuaValue luaValue) {
        return luaValue.raweq(this);
    }

    public boolean equals(Object obj) {
        if (obj instanceof LuaString) {
            return raweq((LuaString) obj);
        }
        return false;
    }

    public LuaValue get(int i) {
        return LuaValue.valueOf(this.c[(this.d + a(i, this.e)) - 1]);
    }

    public LuaValue get(LuaValue luaValue) {
        return luaValue.isnumber() ? get(luaValue.toint()) : super.get(luaValue);
    }

    public LuaValue getmetatable() {
        return b;
    }

    public LuaValue gt(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) < 0 ? LuaValue.TRUE : LuaValue.FALSE : super.gt(luaValue);
    }

    public boolean gt_b(double d) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean gt_b(int i) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean gt_b(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) < 0 : super.gt_b(luaValue);
    }

    public LuaValue gteq(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) <= 0 ? LuaValue.TRUE : LuaValue.FALSE : super.gteq(luaValue);
    }

    public boolean gteq_b(double d) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean gteq_b(int i) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean gteq_b(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) <= 0 : super.gteq_b(luaValue);
    }

    public int hashCode() {
        if (this.i) {
            return this.f;
        }
        this.f = hashCode(this.c, this.d, this.e);
        this.i = true;
        return this.f;
    }

    public int indexOf(byte b2, int i) {
        while (i < this.e) {
            if (this.c[this.d + i] == b2) {
                return i;
            }
            i++;
        }
        return -1;
    }

    public int indexOf(LuaString luaString, int i) {
        int length = luaString.length();
        int i2 = this.e - length;
        while (i <= i2) {
            if (equals(this.c, this.d + i, luaString.c, luaString.d, length)) {
                return i;
            }
            i++;
        }
        return -1;
    }

    public int indexOfAny(LuaString luaString) {
        int i = this.d;
        int i2 = this.e + i;
        int i3 = luaString.d + luaString.e;
        while (i < i2) {
            for (int i4 = luaString.d; i4 < i3; i4++) {
                if (this.c[i] == luaString.c[i4]) {
                    return i - this.d;
                }
            }
            i++;
        }
        return -1;
    }

    public Varargs invoke(Varargs varargs) {
        if (varargs.narg() == 1) {
            LuaValue arg1 = varargs.arg1();
            if ((arg1 instanceof LuaList) && metatag(LuaValue.CALL).isnil()) {
                int length = length();
                int a = a(arg1.get(1).toint(), length);
                int a2 = a(arg1.get(2).toint(), length);
                if (a < 1) {
                    a = 1;
                }
                if (a2 <= length) {
                    length = a2;
                }
                return a <= length ? substring(a - 1, length) : LuaValue.EMPTYSTRING;
            }
        }
        return super.invoke(varargs);
    }

    public boolean isValidUtf8() {
        int index = this.d;
        int end = index + this.e;
        while (index < end) {
            int first = this.c[index++] & 255;
            if (first < 128) {
                continue;
            }

            if (first >= 194 && first <= 223) {
                if (index >= end || (this.c[index++] & 192) != 128) return false;
            } else if (first >= 224 && first <= 239) {
                if (index + 1 >= end) return false;
                int second = this.c[index++] & 255;
                if (second < 128 || second > 191 ||
                    (first == 224 && second < 160) || (first == 237 && second > 159) ||
                    (this.c[index++] & 192) != 128) return false;
            } else if (first >= 240 && first <= 244) {
                if (index + 2 >= end) return false;
                int second = this.c[index++] & 255;
                if (second < 128 || second > 191 ||
                    (first == 240 && second < 144) || (first == 244 && second > 143) ||
                    (this.c[index++] & 192) != 128 || (this.c[index++] & 192) != 128) return false;
            } else {
                return false;
            }
        }
        return true;
    }

    public boolean isint() {
        double scannumber = scannumber();
        return !Double.isNaN(scannumber) && ((double) ((int) scannumber)) == scannumber;
    }

    public boolean islong() {
        double scannumber = scannumber();
        return !Double.isNaN(scannumber) && ((double) ((long) scannumber)) == scannumber;
    }

    public boolean isnumber() {
        return !Double.isNaN(scannumber());
    }

    public boolean isstring() {
        return true;
    }

    public int lastIndexOf(LuaString luaString) {
        int length = luaString.length();
        for (int i = this.e - length; i >= 0; i--) {
            if (equals(this.c, this.d + i, luaString.c, luaString.d, length)) {
                return i;
            }
        }
        return -1;
    }

    public LuaValue len() {
        return LuaInteger.valueOf(this.e);
    }

    public int length() {
        return this.e;
    }

    public int lengthAsUtf8() {
        int index = this.d;
        int end = index + this.e;
        int length = 0;
        while (index < end) {
            int first = this.c[index++] & 255;
            if (first >= 194 && first <= 223 && index < end && (this.c[index] & 192) == 128) {
                index++;
            } else if (first >= 224 && first <= 239 && index + 1 < end &&
                    (this.c[index] & 192) == 128 && (this.c[index + 1] & 192) == 128) {
                index += 2;
            } else if (first >= 240 && first <= 244 && index + 2 < end &&
                    (this.c[index] & 192) == 128 && (this.c[index + 1] & 192) == 128 &&
                    (this.c[index + 2] & 192) == 128) {
                index += 3;
            }
            length++;
        }
        return length;
    }

    public LuaValue lt(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) > 0 ? LuaValue.TRUE : LuaValue.FALSE : super.lt(luaValue);
    }

    public boolean lt_b(double d) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean lt_b(int i) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean lt_b(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) > 0 : super.lt_b(luaValue);
    }

    public LuaValue lteq(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) >= 0 ? LuaValue.TRUE : LuaValue.FALSE : super.lteq(luaValue);
    }

    public boolean lteq_b(double d) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean lteq_b(int i) {
        d("attempt to compare string with number");
        return false;
    }

    public boolean lteq_b(LuaValue luaValue) {
        return luaValue.isstring() ? luaValue.strcmp(this) >= 0 : super.lteq_b(luaValue);
    }

    public int luaByte(int i) {
        return this.c[this.d + i] & 255;
    }

    public LuaValue mod(double d) {
        return LuaDouble.dmod(d(), d);
    }

    public LuaValue mod(int i) {
        return LuaDouble.dmod(d(), i);
    }

    public LuaValue mod(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.MOD, luaValue) : luaValue.modFrom(scannumber);
    }

    public LuaValue modFrom(double d) {
        return LuaDouble.dmod(d, d());
    }

    public LuaValue mul(double d) {
        return LuaValue.valueOf(d() * d);
    }

    public LuaValue mul(int i) {
        return LuaValue.valueOf(d() * i);
    }

    public LuaValue mul(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.MUL, luaValue) : luaValue.mul(scannumber);
    }

    public LuaValue neg() {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? super.neg() : LuaValue.valueOf(-scannumber);
    }

    public double optdouble(double d) {
        return checkdouble();
    }

    public int optint(int i) {
        return checkint();
    }

    public LuaInteger optinteger(LuaInteger luaInteger) {
        return checkinteger();
    }

    public String optjstring(String str) {
        return tojstring();
    }

    public long optlong(long j) {
        return checklong();
    }

    public LuaNumber optnumber(LuaNumber luaNumber) {
        return checknumber();
    }

    public LuaString optstring(LuaString luaString) {
        return this;
    }

    public LuaValue pow(double d) {
        return MathLib.dpow(d(), d);
    }

    public LuaValue pow(int i) {
        return MathLib.dpow(d(), i);
    }

    public LuaValue pow(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.POW, luaValue) : luaValue.powWith(scannumber);
    }

    public LuaValue powWith(double d) {
        return MathLib.dpow(d, d());
    }

    public LuaValue powWith(int i) {
        return MathLib.dpow(i, d());
    }

    public void printToStream(PrintStream printStream) {
        int i = this.e;
        for (int i2 = 0; i2 < i; i2++) {
            printStream.print((char) this.c[this.d + i2]);
        }
    }

    public boolean raweq(LuaString luaString) {
        if (this == luaString) {
            return true;
        }
        if (luaString.e != this.e) {
            return false;
        }
        if (luaString.c == this.c && luaString.d == this.d) {
            return true;
        }
        if (luaString.hashCode() != hashCode()) {
            return false;
        }
        for (int i = 0; i < this.e; i++) {
            if (luaString.c[luaString.d + i] != this.c[this.d + i]) {
                return false;
            }
        }
        return true;
    }

    public boolean raweq(LuaUtf8String luaUtf8String) {
        return raweq(luaUtf8String.tostring());
    }

    public boolean raweq(LuaValue luaValue) {
        return luaValue.raweq(this);
    }

    public int rawlen() {
        return this.e;
    }

    public double scannumber() {
        int i;
        int i2 = this.d;
        int i3 = this.e + i2;
        while (i2 < i3 && this.c[i2] == 32) {
            i2++;
        }
        while (i2 < i3 && this.c[i3 - 1] == 32) {
            i3--;
        }
        if (i2 >= i3) {
            return Double.NaN;
        }
        byte[] bArr = this.c;
        if (bArr[i2] == 48 && (i = i2 + 1) < i3 && ((bArr[i] == 120 || bArr[i] == 88) && i3 > 2)) {
            return a(16, i2 + 2, i3);
        }
        double a = a(10, i2, i3);
        return Double.isNaN(a) ? b(i2, i3) : a;
    }

    public double scannumber(int i) {
        if (i < 2 || i > 36) {
            return Double.NaN;
        }
        int i2 = this.d;
        int i3 = this.e + i2;
        while (i2 < i3 && this.c[i2] == 32) {
            i2++;
        }
        while (i2 < i3 && this.c[i3 - 1] == 32) {
            i3--;
        }
        if (i2 >= i3) {
            return Double.NaN;
        }
        return a(i, i2, i3);
    }

    public int strcmp(LuaString luaString) {
        int i = 0;
        for (int i2 = 0; i < this.e && i2 < luaString.e; i2++) {
            byte[] bArr = this.c;
            int i3 = this.d;
            byte b2 = bArr[i3 + i];
            byte[] bArr2 = luaString.c;
            int i4 = luaString.d;
            if (b2 != bArr2[i4 + i2]) {
                return bArr[i3 + i] - bArr2[i4 + i2];
            }
            i++;
        }
        return this.e - luaString.e;
    }

    public int strcmp(LuaValue luaValue) {
        return -luaValue.strcmp(this);
    }

    public LuaString strvalue() {
        return this;
    }

    public LuaValue sub(double d) {
        return LuaValue.valueOf(d() - d);
    }

    public LuaValue sub(int i) {
        return LuaValue.valueOf(d() - i);
    }

    public LuaValue sub(LuaValue luaValue) {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? a(LuaValue.SUB, luaValue) : luaValue.subFrom(scannumber);
    }

    public LuaValue subFrom(double d) {
        return LuaValue.valueOf(d - d());
    }

    public LuaString substring(int i, int i2) {
        int i3 = this.d + i;
        int i4 = i2 - i;
        return i4 >= this.e / 2 ? valueUsing(this.c, i3, i4) : valueOf(this.c, i3, i4);
    }

    public char[] toCharArray() {
        if (this.g == null) {
            this.g = toCharAsUtf8(this.c, this.d, this.e);
        }
        return this.g;
    }

    public InputStream toInputStream() {
        return new ByteArrayInputStream(this.c, this.d, this.e);
    }

    public byte tobyte() {
        return (byte) toint();
    }

    public char tochar() {
        return (char) toint();
    }

    public double todouble() {
        double scannumber = scannumber();
        if (Double.isNaN(scannumber)) {
            return 0.0d;
        }
        return scannumber;
    }

    public float tofloat() {
        return (float) todouble();
    }

    public int toint() {
        return (int) tolong();
    }

    public LuaValue tointeger() {
        Long e = e();
        return e == null ? LuaValue.NIL : LuaValue.valueOf(e);
    }

    public LuaValue tointeger(int i) {
        Long a = a(i);
        return a == null ? LuaValue.NIL : LuaValue.valueOf(a);
    }

    public String tojstring() {
        if (this.h == null) {
            this.h = decodeAsUtf8(this.c, this.d, this.e);
        }
        return this.h;
    }

    public long tolong() {
        return (long) todouble();
    }

    public LuaValue tonumber() {
        double scannumber = scannumber();
        return Double.isNaN(scannumber) ? LuaValue.NIL : LuaValue.valueOf(scannumber);
    }

    public LuaValue tonumber(int i) {
        double scannumber = scannumber(i);
        return Double.isNaN(scannumber) ? LuaValue.NIL : LuaValue.valueOf(scannumber);
    }

    public short toshort() {
        return (short) toint();
    }

    public LuaValue tostring() {
        return this;
    }

    public int type() {
        return 4;
    }

    public String typename() {
        return "string";
    }

    public void write(DataOutputStream dataOutputStream, int i, int i2) {
        try {
            dataOutputStream.write(this.c, this.d + i, i2);
        } catch (IOException exception) {
            throw new RuntimeException(exception);
        }
    }
}

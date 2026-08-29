//
// Decompiled by Jadx - 591ms
//
package org.luaj;

import java.io.PrintStream;
import org.luaj.lib.MathLib;

public class LuaUtf8String extends LuaValue {
    public static LuaValue b;
    public final int[] c;
    public final int d;
    public final int e;
    private int f;
    private boolean g;
    private String h;
    private LuaString i;

    private LuaUtf8String(int[] iArr, int i, int i2) {
        this.c = iArr;
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
            int[] iArr = this.c;
            int i4 = iArr[i2];
            int i5 = 48;
            if (i > 10 && (iArr[i2] < 48 || iArr[i2] > 57)) {
                int[] iArr2 = this.c;
                i5 = (iArr2[i2] < 65 || iArr2[i2] > 90) ? 87 : 55;
            }
            int i6 = i4 - i5;
            if (i6 < 0 || i6 >= i) {
                return Double.NaN;
            }
            j = (j * i) + i6;
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

    private double b(int i, int i2) {
        int i3 = i + 64;
        if (i2 > i3) {
            i2 = i3;
        }
        for (int i4 = i; i4 < i2; i4++) {
            int i5 = this.c[i4];
            if (i5 != 43 && i5 != 69 && i5 != 101 && i5 != 45 && i5 != 46) {
                switch (i5) {
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
        int[] iArr = new int[i2 - i];
        System.arraycopy(this.c, i, iArr, 0, iArr.length);
        try {
            return Double.parseDouble(new String(iArr, 0, iArr.length));
        } catch (Exception unused) {
            return Double.NaN;
        }
    }

    private double d() {
        double scannumber = scannumber();
        if (Double.isNaN(scannumber)) {
            a();
        }
        return scannumber;
    }

    public static String decodeAsUtf8(int[] iArr, int i, int i2) {
        return new String(iArr, i, i2);
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

    public static boolean equals(LuaUtf8String luaUtf8String, int i, LuaUtf8String luaUtf8String2, int i2, int i3) {
        return equals(luaUtf8String.c, luaUtf8String.d + i, luaUtf8String2.c, luaUtf8String2.d + i2, i3);
    }

    public static boolean equals(int[] iArr, int i, int[] iArr2, int i2, int i3) {
        if (iArr.length < i + i3 || iArr2.length < i2 + i3) {
            return false;
        }
        while (true) {
            i3--;
            if (i3 < 0) {
                return true;
            }
            int i4 = i + 1;
            int i5 = i2 + 1;
            if (iArr[i] != iArr2[i2]) {
                return false;
            }
            i = i4;
            i2 = i5;
        }
    }

    public static int hashCode(int[] iArr, int i, int i2) {
        int i3 = (i2 >> 5) + 1;
        int i4 = i2;
        while (i2 >= i3) {
            i4 ^= ((i4 << 5) + (i4 >> 2)) + (iArr[(i + i2) - 1] & 255);
            i2 -= i3;
        }
        return i4;
    }

    public static int lengthAsUtf8(int[] iArr) {
        int length = iArr.length;
        int i = length;
        while (true) {
            length--;
            if (length < 0) {
                return i;
            }
            int i2 = iArr[length];
            if (i2 >= 128) {
                i += i2 >= 2048 ? 2 : 1;
            }
        }
    }

    public static LuaString toLuaString(int[] iArr, int i, int i2) {
        return LuaString.valueOf(new String(iArr, i, i2));
    }

    public static LuaUtf8String valueOf(int[] iArr) {
        return valueOf(iArr, 0, iArr.length);
    }

    public static LuaUtf8String valueOf(int[] iArr, int i, int i2) {
        return valueUsing(iArr, i, i2);
    }

    public static LuaUtf8String valueOfString(String str) {
        int codePointCount = str.codePointCount(0, str.length());
        int[] iArr = new int[codePointCount];
        int i = 0;
        for (int i2 = 0; i2 < codePointCount; i2++) {
            iArr[i2] = str.codePointAt(i);
            i += Character.charCount(iArr[i2]);
        }
        return valueUsing(iArr, 0, iArr.length);
    }

    public static LuaUtf8String valueOfString(LuaString luaString) {
        return valueOfString(luaString.tojstring());
    }

    public static LuaUtf8String valueUsing(int[] iArr) {
        return valueUsing(iArr, 0, iArr.length);
    }

    public static LuaUtf8String valueUsing(int[] iArr, int i, int i2) {
        return new LuaUtf8String(iArr, i, i2);
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
        return strvalue();
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

    public LuaValue concatTo(LuaUtf8String luaUtf8String) {
        int i = luaUtf8String.e;
        int[] iArr = new int[this.e + i];
        System.arraycopy(luaUtf8String.c, luaUtf8String.d, iArr, 0, i);
        System.arraycopy(this.c, this.d, iArr, luaUtf8String.e, this.e);
        return valueUsing(iArr, 0, iArr.length);
    }

    public void copyInto(int i, int[] iArr, int i2, int i3) {
        System.arraycopy(this.c, this.d + i, iArr, i2, i3);
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
        if (obj instanceof LuaUtf8String) {
            return raweq((LuaUtf8String) obj);
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
        if (this.g) {
            return this.f;
        }
        this.f = tostring().hashCode();
        this.g = true;
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

    public int indexOf(LuaUtf8String luaUtf8String, int i) {
        int length = luaUtf8String.length();
        int i2 = this.e - length;
        while (i <= i2) {
            if (equals(this.c, this.d + i, luaUtf8String.c, luaUtf8String.d, length)) {
                return i;
            }
            i++;
        }
        return -1;
    }

    public int indexOfAny(LuaUtf8String luaUtf8String) {
        int i = this.d;
        int i2 = this.e + i;
        int i3 = luaUtf8String.d + luaUtf8String.e;
        while (i < i2) {
            for (int i4 = luaUtf8String.d; i4 < i3; i4++) {
                if (this.c[i] == luaUtf8String.c[i4]) {
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
        for (int index = this.d, end = index + this.e; index < end; index++) {
            int codePoint = this.c[index];
            if (codePoint < 0 || codePoint > 0x10ffff || (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
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

    public int lastIndexOf(LuaUtf8String luaUtf8String) {
        int length = luaUtf8String.length();
        for (int i = this.e - length; i >= 0; i--) {
            if (equals(this.c, this.d + i, luaUtf8String.c, luaUtf8String.d, length)) {
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
        return this.c[this.d + i];
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
        return strvalue();
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
        return strvalue().raweq(luaString);
    }

    public boolean raweq(LuaUtf8String luaUtf8String) {
        if (this == luaUtf8String) {
            return true;
        }
        if (luaUtf8String.e != this.e) {
            return false;
        }
        if (luaUtf8String.c == this.c && luaUtf8String.d == this.d) {
            return true;
        }
        if (luaUtf8String.hashCode() != hashCode()) {
            return false;
        }
        for (int i = 0; i < this.e; i++) {
            if (luaUtf8String.c[luaUtf8String.d + i] != this.c[this.d + i]) {
                return false;
            }
        }
        return true;
    }

    public boolean raweq(LuaValue luaValue) {
        return luaValue instanceof LuaUtf8String ? raweq((LuaUtf8String) luaValue) : luaValue.raweq(this);
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
        int[] iArr = this.c;
        if (iArr[i2] == 48 && (i = i2 + 1) < i3 && (iArr[i] == 120 || iArr[i] == 88)) {
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

    public int strcmp(LuaUtf8String luaUtf8String) {
        int i = 0;
        for (int i2 = 0; i < this.e && i2 < luaUtf8String.e; i2++) {
            int[] iArr = this.c;
            int i3 = this.d;
            int i4 = iArr[i3 + i];
            int[] iArr2 = luaUtf8String.c;
            int i5 = luaUtf8String.d;
            if (i4 != iArr2[i5 + i2]) {
                return iArr[i3 + i] - iArr2[i5 + i2];
            }
            i++;
        }
        return this.e - luaUtf8String.e;
    }

    public int strcmp(LuaValue luaValue) {
        return -luaValue.strcmp(this);
    }

    public LuaString strvalue() {
        if (this.i == null) {
            this.i = toLuaString(this.c, this.d, this.e);
        }
        return this.i;
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

    public LuaUtf8String substring(int i, int i2) {
        int i3 = this.d + i;
        int i4 = i2 - i;
        return i4 >= this.e / 2 ? valueUsing(this.c, i3, i4) : valueOf(this.c, i3, i4);
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
        return strvalue();
    }

    public int type() {
        return 4;
    }

    public String typename() {
        return "string";
    }
}

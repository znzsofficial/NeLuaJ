/*
 * Copyright (C) 2011 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package dx;

import dx.rop.cst.CstBoolean;
import dx.rop.cst.CstByte;
import dx.rop.cst.CstChar;
import dx.rop.cst.CstDouble;
import dx.rop.cst.CstFloat;
import dx.rop.cst.CstInteger;
import dx.rop.cst.CstKnownNull;
import dx.rop.cst.CstLong;
import dx.rop.cst.CstShort;
import dx.rop.cst.CstString;
import dx.rop.cst.CstType;
import dx.rop.cst.TypedConstant;

/**
 * Factory for rop constants.
 */
final class Constants {
    private Constants() {}

    /**
     * Returns a rop constant for the specified value.
     *
     * @param value null, a boxed primitive, String, Class, or TypeId.
     */
    static TypedConstant getConstant(Object value) {
        if (value == null) {
            return CstKnownNull.THE_ONE;
        } else if (value instanceof Boolean) {
            return CstBoolean.make((Boolean) value);
        } else if (value instanceof Byte) {
            return CstByte.make((Byte) value);
        } else if (value instanceof Character) {
            return CstChar.make((Character) value);
        } else if (value instanceof Double) {
            return CstDouble.make(Double.doubleToLongBits((Double) value));
        } else if (value instanceof Float) {
            return CstFloat.make(Float.floatToIntBits((Float) value));
        } else if (value instanceof Integer) {
            return CstInteger.make((Integer) value);
        } else if (value instanceof Long) {
            return CstLong.make((Long) value);
        } else if (value instanceof Short) {
            return CstShort.make((Short) value);
        } else if (value instanceof String) {
            return new CstString((String) value);
        } else if (value instanceof Class) {
            return new CstType(TypeId.get((Class<?>) value).ropType);
        } else if (value instanceof TypeId) {
            return new CstType(((TypeId) value).ropType);
        } else {
            throw new UnsupportedOperationException("Not a constant: " + value);
        }
    }
}

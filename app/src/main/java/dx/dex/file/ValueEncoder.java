/*
 * Copyright (C) 2008 The Android Open Source Project
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

package dx.dex.file;

import java.util.Collection;

import dx.rop.annotation.Annotation;
import dx.rop.annotation.NameValuePair;
import dx.rop.cst.Constant;
import dx.rop.cst.CstAnnotation;
import dx.rop.cst.CstArray;
import dx.rop.cst.CstBoolean;
import dx.rop.cst.CstByte;
import dx.rop.cst.CstChar;
import dx.rop.cst.CstDouble;
import dx.rop.cst.CstEnumRef;
import dx.rop.cst.CstFieldRef;
import dx.rop.cst.CstFloat;
import dx.rop.cst.CstInteger;
import dx.rop.cst.CstKnownNull;
import dx.rop.cst.CstLiteralBits;
import dx.rop.cst.CstLong;
import dx.rop.cst.CstMethodRef;
import dx.rop.cst.CstShort;
import dx.rop.cst.CstString;
import dx.rop.cst.CstType;
import dx.util.AnnotatedOutput;
import dx.util.Hex;

/**
 * Handler for writing out {@code encoded_values} and parts
 * thereof.
 */
public final class ValueEncoder {
    /** annotation value type constant: {@code byte} */
    private static final int VALUE_BYTE = 0x00;

    /** annotation value type constant: {@code short} */
    private static final int VALUE_SHORT = 0x02;

    /** annotation value type constant: {@code char} */
    private static final int VALUE_CHAR = 0x03;

    /** annotation value type constant: {@code int} */
    private static final int VALUE_INT = 0x04;

    /** annotation value type constant: {@code long} */
    private static final int VALUE_LONG = 0x06;

    /** annotation value type constant: {@code float} */
    private static final int VALUE_FLOAT = 0x10;

    /** annotation value type constant: {@code double} */
    private static final int VALUE_DOUBLE = 0x11;

    /** annotation value type constant: {@code string} */
    private static final int VALUE_STRING = 0x17;

    /** annotation value type constant: {@code type} */
    private static final int VALUE_TYPE = 0x18;

    /** annotation value type constant: {@code field} */
    private static final int VALUE_FIELD = 0x19;

    /** annotation value type constant: {@code method} */
    private static final int VALUE_METHOD = 0x1a;

    /** annotation value type constant: {@code enum} */
    private static final int VALUE_ENUM = 0x1b;

    /** annotation value type constant: {@code array} */
    private static final int VALUE_ARRAY = 0x1c;

    /** annotation value type constant: {@code annotation} */
    private static final int VALUE_ANNOTATION = 0x1d;

    /** annotation value type constant: {@code null} */
    private static final int VALUE_NULL = 0x1e;

    /** annotation value type constant: {@code boolean} */
    private static final int VALUE_BOOLEAN = 0x1f;

    /** {@code non-null;} file being written */
    private final DexFile file;

    /** {@code non-null;} output stream to write to */
    private final AnnotatedOutput out;

    /**
     * Construct an instance.
     *
     * @param file {@code non-null;} file being written
     * @param out {@code non-null;} output stream to write to
     */
    public ValueEncoder(DexFile file, AnnotatedOutput out) {
        if (file == null) {
            throw new NullPointerException("file == null");
        }

        if (out == null) {
            throw new NullPointerException("out == null");
        }

        this.file = file;
        this.out = out;
    }

    /**
     * Writes out the encoded form of the given constant.
     *
     * @param cst {@code non-null;} the constant to write
     */
    public void writeConstant(Constant cst) {
        int type = constantToValueType(cst);
        int arg;

        switch (type) {
            case VALUE_BYTE:
            case VALUE_SHORT:
            case VALUE_INT:
            case VALUE_LONG: {
                long value = ((CstLiteralBits) cst).getLongBits();
                writeSignedIntegralValue(type, value);
                break;
            }
            case VALUE_CHAR: {
                long value = ((CstLiteralBits) cst).getLongBits();
                writeUnsignedIntegralValue(type, value);
                break;
            }
            case VALUE_FLOAT: {
                // Shift value left 32 so that right-zero-extension works.
                long value = ((CstFloat) cst).getLongBits() << 32;
                writeRightZeroExtendedValue(type, value);
                break;
            }
            case VALUE_DOUBLE: {
                long value = ((CstDouble) cst).getLongBits();
                writeRightZeroExtendedValue(type, value);
                break;
            }
            case VALUE_STRING: {
                int index = file.getStringIds().indexOf((CstString) cst);
                writeUnsignedIntegralValue(type, index);
                break;
            }
            case VALUE_TYPE: {
                int index = file.getTypeIds().indexOf((CstType) cst);
                writeUnsignedIntegralValue(type, index);
                break;
            }
            case VALUE_FIELD: {
                int index = file.getFieldIds().indexOf((CstFieldRef) cst);
                writeUnsignedIntegralValue(type, index);
                break;
            }
            case VALUE_METHOD: {
                int index = file.getMethodIds().indexOf((CstMethodRef) cst);
                writeUnsignedIntegralValue(type, index);
                break;
            }
            case VALUE_ENUM: {
                CstFieldRef fieldRef = ((CstEnumRef) cst).getFieldRef();
                int index = file.getFieldIds().indexOf(fieldRef);
                writeUnsignedIntegralValue(type, index);
                break;
            }
            case VALUE_ARRAY: {
                out.writeByte(type);
                writeArray((CstArray) cst, false);
                break;
            }
            case VALUE_ANNOTATION: {
                out.writeByte(type);
                writeAnnotation(((CstAnnotation) cst).getAnnotation(),
                        false);
                break;
            }
            case VALUE_NULL: {
                out.writeByte(type);
                break;
            }
            case VALUE_BOOLEAN: {
                int value = ((CstBoolean) cst).getIntBits();
                out.writeByte(type | (value << 5));
                break;
            }
            default: {
                throw new RuntimeException("Shouldn't happen");
            }
        }
    }

    /**
     * Gets the value type for the given constant.
     *
     * @param cst {@code non-null;} the constant
     * @return the value type; one of the {@code VALUE_*} constants
     * defined by this class
     */
    private static int constantToValueType(Constant cst) {
        /*
         * TODO: Constant should probable have an associated enum, so this
         * can be a switch().
         */
        if (cst instanceof CstByte) {
            return VALUE_BYTE;
        } else if (cst instanceof CstShort) {
            return VALUE_SHORT;
        } else if (cst instanceof CstChar) {
            return VALUE_CHAR;
        } else if (cst instanceof CstInteger) {
            return VALUE_INT;
        } else if (cst instanceof CstLong) {
            return VALUE_LONG;
        } else if (cst instanceof CstFloat) {
            return VALUE_FLOAT;
        } else if (cst instanceof CstDouble) {
            return VALUE_DOUBLE;
        } else if (cst instanceof CstString) {
            return VALUE_STRING;
        } else if (cst instanceof CstType) {
            return VALUE_TYPE;
        } else if (cst instanceof CstFieldRef) {
            return VALUE_FIELD;
        } else if (cst instanceof CstMethodRef) {
            return VALUE_METHOD;
        } else if (cst instanceof CstEnumRef) {
            return VALUE_ENUM;
        } else if (cst instanceof CstArray) {
            return VALUE_ARRAY;
        } else if (cst instanceof CstAnnotation) {
            return VALUE_ANNOTATION;
        } else if (cst instanceof CstKnownNull) {
            return VALUE_NULL;
        } else if (cst instanceof CstBoolean) {
            return VALUE_BOOLEAN;
        } else {
            throw new RuntimeException("Shouldn't happen");
        }
    }

    /**
     * Writes out the encoded form of the given array, that is, as
     * an {@code encoded_array} and not including a
     * {@code value_type} prefix. If the output stream keeps
     * (debugging) annotations and {@code topLevel} is
     * {@code true}, then this method will write (debugging)
     * annotations.
     *
     * @param array {@code non-null;} array instance to write
     * @param topLevel {@code true} iff the given annotation is the
     * top-level annotation or {@code false} if it is a sub-annotation
     * of some other annotation
     */
    public void writeArray(CstArray array, boolean topLevel) {
        boolean annotates = topLevel && out.annotates();
        CstArray.List list = array.getList();
        int size = list.size();

        if (annotates) {
            out.annotate("  size: " + Hex.u4(size));
        }

        out.writeUleb128(size);

        for (int i = 0; i < size; i++) {
            Constant cst = list.get(i);
            if (annotates) {
                out.annotate("  [" + Integer.toHexString(i) + "] " +
                        constantToHuman(cst));
            }
            writeConstant(cst);
        }

        if (annotates) {
            out.endAnnotation();
        }
    }

    /**
     * Writes out the encoded form of the given annotation, that is,
     * as an {@code encoded_annotation} and not including a
     * {@code value_type} prefix. If the output stream keeps
     * (debugging) annotations and {@code topLevel} is
     * {@code true}, then this method will write (debugging)
     * annotations.
     *
     * @param annotation {@code non-null;} annotation instance to write
     * @param topLevel {@code true} iff the given annotation is the
     * top-level annotation or {@code false} if it is a sub-annotation
     * of some other annotation
     */
    public void writeAnnotation(Annotation annotation, boolean topLevel) {
        boolean annotates = topLevel && out.annotates();
        StringIdsSection stringIds = file.getStringIds();
        TypeIdsSection typeIds = file.getTypeIds();

        CstType type = annotation.getType();
        int typeIdx = typeIds.indexOf(type);

        if (annotates) {
            out.annotate("  type_idx: " + Hex.u4(typeIdx) + " // " +
                    type.toHuman());
        }

        out.writeUleb128(typeIds.indexOf(annotation.getType()));

        Collection<NameValuePair> pairs = annotation.getNameValuePairs();
        int size = pairs.size();

        if (annotates) {
            out.annotate("  size: " + Hex.u4(size));
        }

        out.writeUleb128(size);

        int at = 0;
        for (NameValuePair pair : pairs) {
            CstString name = pair.getName();
            int nameIdx = stringIds.indexOf(name);
            Constant value = pair.getValue();

            if (annotates) {
                out.annotate(0, "  elements[" + at + "]:");
                at++;
                out.annotate("    name_idx: " + Hex.u4(nameIdx) + " // " +
                        name.toHuman());
            }

            out.writeUleb128(nameIdx);

            if (annotates) {
                out.annotate("    value: " + constantToHuman(value));
            }

            writeConstant(value);
        }

        if (annotates) {
            out.endAnnotation();
        }
    }

    /**
     * Gets the colloquial type name and human form of the type of the
     * given constant, when used as an encoded value.
     *
     * @param cst {@code non-null;} the constant
     * @return {@code non-null;} its type name and human form
     */
    public static String constantToHuman(Constant cst) {
        int type = constantToValueType(cst);

        if (type == VALUE_NULL) {
            return "null";
        }
        return cst.typeName() +
                ' ' +
                cst.toHuman();
    }

    /**
     * Helper for {@link #writeConstant}, which writes out the value
     * for any signed integral type.
     *
     * @param type the type constant
     * @param value {@code long} bits of the value
     */
    private void writeSignedIntegralValue(int type, long value) {
        /*
         * Figure out how many bits are needed to represent the value,
         * including a sign bit: The bit count is subtracted from 65
         * and not 64 to account for the sign bit. The xor operation
         * has the effect of leaving non-negative values alone and
         * unary complementing negative values (so that a leading zero
         * count always returns a useful number for our present
         * purpose).
         */
        int requiredBits =
            65 - Long.numberOfLeadingZeros(value ^ (value >> 63));

        // Round up the requiredBits to a number of bytes.
        int requiredBytes = (requiredBits + 0x07) >> 3;

        /*
         * Write the header byte, which includes the type and
         * requiredBytes - 1.
         */
        out.writeByte(type | ((requiredBytes - 1) << 5));

        // Write the value, per se.
        while (requiredBytes > 0) {
            out.writeByte((byte) value);
            value >>= 8;
            requiredBytes--;
        }
    }

    /**
     * Helper for {@link #writeConstant}, which writes out the value
     * for any unsigned integral type.
     *
     * @param type the type constant
     * @param value {@code long} bits of the value
     */
    private void writeUnsignedIntegralValue(int type, long value) {
        // Figure out how many bits are needed to represent the value.
        int requiredBits = 64 - Long.numberOfLeadingZeros(value);
        if (requiredBits == 0) {
            requiredBits = 1;
        }

        // Round up the requiredBits to a number of bytes.
        int requiredBytes = (requiredBits + 0x07) >> 3;

        /*
         * Write the header byte, which includes the type and
         * requiredBytes - 1.
         */
        out.writeByte(type | ((requiredBytes - 1) << 5));

        // Write the value, per se.
        while (requiredBytes > 0) {
            out.writeByte((byte) value);
            value >>= 8;
            requiredBytes--;
        }
    }

    /**
     * Helper for {@link #writeConstant}, which writes out a
     * right-zero-extended value.
     *
     * @param type the type constant
     * @param value {@code long} bits of the value
     */
    private void writeRightZeroExtendedValue(int type, long value) {
        // Figure out how many bits are needed to represent the value.
        int requiredBits = 64 - Long.numberOfTrailingZeros(value);
        if (requiredBits == 0) {
            requiredBits = 1;
        }

        // Round up the requiredBits to a number of bytes.
        int requiredBytes = (requiredBits + 0x07) >> 3;

        // Scootch the first bits to be written down to the low-order bits.
        value >>= 64 - (requiredBytes * 8);

        /*
         * Write the header byte, which includes the type and
         * requiredBytes - 1.
         */
        out.writeByte(type | ((requiredBytes - 1) << 5));

        // Write the value, per se.
        while (requiredBytes > 0) {
            out.writeByte((byte) value);
            value >>= 8;
            requiredBytes--;
        }
    }


    /**
     * Helper for {@code addContents()} methods, which adds
     * contents for a particular {@link Annotation}, calling itself
     * recursively should it encounter a nested annotation.
     *
     * @param file {@code non-null;} the file to add to
     * @param annotation {@code non-null;} the annotation to add contents for
     */
    public static void addContents(DexFile file, Annotation annotation) {
        TypeIdsSection typeIds = file.getTypeIds();
        StringIdsSection stringIds = file.getStringIds();

        typeIds.intern(annotation.getType());

        for (NameValuePair pair : annotation.getNameValuePairs()) {
            stringIds.intern(pair.getName());
            addContents(file, pair.getValue());
        }
    }

    /**
     * Helper for {@code addContents()} methods, which adds
     * contents for a particular constant, calling itself recursively
     * should it encounter a {@link CstArray} and calling {@link
     * #addContents(DexFile,Annotation)} recursively should it
     * encounter a {@link CstAnnotation}.
     *
     * @param file {@code non-null;} the file to add to
     * @param cst {@code non-null;} the constant to add contents for
     */
    public static void addContents(DexFile file, Constant cst) {
        if (cst instanceof CstAnnotation) {
            addContents(file, ((CstAnnotation) cst).getAnnotation());
        } else if (cst instanceof CstArray) {
            CstArray.List list = ((CstArray) cst).getList();
            int size = list.size();
            for (int i = 0; i < size; i++) {
                addContents(file, list.get(i));
            }
        } else {
            file.internIfAppropriate(cst);
        }
    }
}

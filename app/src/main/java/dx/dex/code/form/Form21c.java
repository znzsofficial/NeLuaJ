/*
 * Copyright (C) 2007 The Android Open Source Project
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

package dx.dex.code.form;

import java.util.BitSet;

import dx.dex.code.CstInsn;
import dx.dex.code.DalvInsn;
import dx.dex.code.InsnFormat;
import dx.rop.code.RegisterSpec;
import dx.rop.code.RegisterSpecList;
import dx.rop.cst.Constant;
import dx.rop.cst.CstFieldRef;
import dx.rop.cst.CstString;
import dx.rop.cst.CstType;
import dx.util.AnnotatedOutput;

/**
 * Instruction format {@code 21c}. See the instruction format spec
 * for details.
 */
public final class Form21c extends InsnFormat {
    /** {@code non-null;} unique instance of this class */
    public static final InsnFormat THE_ONE = new Form21c();

    /**
     * Constructs an instance. This class is not publicly
     * instantiable. Use {@link #THE_ONE}.
     */
    private Form21c() {
        // This space intentionally left blank.
    }

    /** {@inheritDoc} */
    @Override
    public String insnArgString(DalvInsn insn) {
        RegisterSpecList regs = insn.getRegisters();
        return regs.get(0).regString() + ", " + cstString(insn);
    }

    /** {@inheritDoc} */
    @Override
    public String insnCommentString(DalvInsn insn, boolean noteIndices) {
        if (noteIndices) {
            return cstComment(insn);
        } else {
            return "";
        }
    }

    /** {@inheritDoc} */
    @Override
    public int codeSize() {
        return 2;
    }

    /** {@inheritDoc} */
    @Override
    public boolean isCompatible(DalvInsn insn) {
        if (!(insn instanceof CstInsn ci)) {
            return false;
        }

        RegisterSpecList regs = insn.getRegisters();
        RegisterSpec reg;

        switch (regs.size()) {
            case 1: {
                reg = regs.get(0);
                break;
            }
            case 2: {
                /*
                 * This format is allowed for ops that are effectively
                 * 2-arg but where the two args are identical.
                 */
                reg = regs.get(0);
                if (reg.getReg() != regs.get(1).getReg()) {
                    return false;
                }
                break;
            }
            default: {
                return false;
            }
        }

        if (!unsignedFitsInByte(reg.getReg())) {
            return false;
        }

        int cpi = ci.getIndex();
        Constant cst = ci.getConstant();

        if (! unsignedFitsInShort(cpi)) {
            return false;
        }

        return (cst instanceof CstType) ||
            (cst instanceof CstFieldRef) ||
            (cst instanceof CstString);
    }

    /** {@inheritDoc} */
    @Override
    public BitSet compatibleRegs(DalvInsn insn) {
        RegisterSpecList regs = insn.getRegisters();
        int sz = regs.size();
        BitSet bits = new BitSet(sz);
        boolean compat = unsignedFitsInByte(regs.get(0).getReg());

        if (sz == 1) {
            bits.set(0, compat);
        } else {
            if (regs.get(0).getReg() == regs.get(1).getReg()) {
                bits.set(0, compat);
                bits.set(1, compat);
            }
        }

        return bits;
    }

    /** {@inheritDoc} */
    @Override
    public void writeTo(AnnotatedOutput out, DalvInsn insn) {
        RegisterSpecList regs = insn.getRegisters();
        int cpi = ((CstInsn) insn).getIndex();

        write(out,
              opcodeUnit(insn, regs.get(0).getReg()),
              (short) cpi);
    }
}

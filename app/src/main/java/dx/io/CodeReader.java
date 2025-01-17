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

package dx.io;

import dx.io.instructions.DecodedInstruction;
import dx.util.DexException;

/**
 * Walks through a block of code and calls visitor call backs.
 */
public final class CodeReader {
    private Visitor fallbackVisitor = null;
    private Visitor stringVisitor = null;
    private Visitor typeVisitor = null;
    private Visitor fieldVisitor = null;
    private Visitor methodVisitor = null;

    /**
     * Sets {@code visitor} as the visitor for all instructions.
     */
    public void setAllVisitors(Visitor visitor) {
        fallbackVisitor = visitor;
        stringVisitor = visitor;
        typeVisitor = visitor;
        fieldVisitor = visitor;
        methodVisitor = visitor;
    }

    /**
     * Sets {@code visitor} as the visitor for all instructions not
     * otherwise handled.
     */
    public void setFallbackVisitor(Visitor visitor) {
        fallbackVisitor = visitor;
    }

    /**
     * Sets {@code visitor} as the visitor for all string instructions.
     */
    public void setStringVisitor(Visitor visitor) {
        stringVisitor = visitor;
    }

    /**
     * Sets {@code visitor} as the visitor for all type instructions.
     */
    public void setTypeVisitor(Visitor visitor) {
        typeVisitor = visitor;
    }

    /**
     * Sets {@code visitor} as the visitor for all field instructions.
     */
    public void setFieldVisitor(Visitor visitor) {
        fieldVisitor = visitor;
    }

    /**
     * Sets {@code visitor} as the visitor for all method instructions.
     */
    public void setMethodVisitor(Visitor visitor) {
        methodVisitor = visitor;
    }

    public void visitAll(DecodedInstruction[] decodedInstructions)
            throws DexException {
        int size = decodedInstructions.length;

        for (int i = 0; i < size; i++) {
            DecodedInstruction one = decodedInstructions[i];
            if (one == null) {
                continue;
            }

            callVisit(decodedInstructions, one);
        }
    }

    public void visitAll(short[] encodedInstructions) throws DexException {
        DecodedInstruction[] decodedInstructions =
            DecodedInstruction.decodeAll(encodedInstructions);
        visitAll(decodedInstructions);
    }

    private void callVisit(DecodedInstruction[] all, DecodedInstruction one) {
        Visitor visitor = switch (OpcodeInfo.getIndexType(one.getOpcode())) {
            case STRING_REF -> stringVisitor;
            case TYPE_REF -> typeVisitor;
            case FIELD_REF -> fieldVisitor;
            case METHOD_REF -> methodVisitor;
            default -> null;
        };

        if (visitor == null) {
            visitor = fallbackVisitor;
        }

        if (visitor != null) {
            visitor.visit(all, one);
        }
    }

    public interface Visitor {
        void visit(DecodedInstruction[] all, DecodedInstruction one);
    }
}

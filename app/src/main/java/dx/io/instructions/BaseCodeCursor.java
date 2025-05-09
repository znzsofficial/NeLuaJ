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

package dx.io.instructions;


/**
 * Base implementation of {@link CodeCursor}.
 */
public abstract class BaseCodeCursor implements CodeCursor {
    /** base address map */
    private final AddressMap baseAddressMap;

    /** next index within {@link #array} to read from or write to */
    private int cursor;

    /**
     * Constructs an instance.
     */
    public BaseCodeCursor() {
        this.baseAddressMap = new AddressMap();
        this.cursor = 0;
    }

    /** @inheritDoc */
    public final int cursor() {
        return cursor;
    }

    /** @inheritDoc */
    public final int baseAddressForCursor() {
        int mapped = baseAddressMap.get(cursor);
        return (mapped >= 0) ? mapped : cursor;
    }

    /** @inheritDoc */
    public final void setBaseAddress(int targetAddress, int baseAddress) {
        baseAddressMap.put(targetAddress, baseAddress);
    }

    /**
     * Advance the cursor by the indicated amount.
     */
    protected final void advance() {
        cursor += 1;
    }
}

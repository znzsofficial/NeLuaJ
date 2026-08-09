package org.luaj.lib.jse;

import org.junit.Test;
import org.luaj.Globals;
import org.luaj.LuaString;
import org.luaj.LuaUtf8String;
import org.luaj.LuaValue;
import org.luaj.Varargs;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Array;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

public class JseBridgeTest {
    @Test
    public void finalInstanceFieldsAreNotSharedAcrossWrappers() {
        JavaInstance first = new JavaInstance(new User(1));
        JavaInstance second = new JavaInstance(new User(2));
        LuaValue id = LuaValue.valueOf("id");

        assertEquals(1, first.get(id).toint());
        assertEquals(2, second.get(id).toint());
    }

    @Test
    public void javaClassSpecialMembersDoNotChangeStaticMemberLookup() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local Integer = luajava.bindClass('java.lang.Integer'); " +
                "local array = Integer.array({1, 2}); " +
                "return Integer.MAX_VALUE, Integer.class.name, Integer.new ~= nil, Integer.override ~= nil, #array"
        ).invoke();

        assertEquals(Integer.MAX_VALUE, result.arg1().toint());
        assertEquals("java.lang.Integer", result.arg(2).tojstring());
        assertTrue(result.arg(3).toboolean());
        assertTrue(result.arg(4).toboolean());
        assertEquals(2, result.arg(5).toint());
    }

    @Test
    public void sandboxGlobalsKeepSafeLibrariesAndExcludeJseEntrypoints() {
        Globals sandbox = JsePlatform.sandboxGlobals();

        assertEquals(7, sandbox.load("return math.max(3, 7)").call().toint());
        for (String name : new String[]{"coroutine", "string", "table", "math", "utf8", "bit32"}) {
            assertFalse(name, sandbox.get(name).isnil());
        }
        for (String name : new String[]{
            "io", "os", "package", "debug", "luajava", "import", "require", "dofile", "loadfile",
            "collectgarbage", "gcinfo", "newproxy", "module"
        }) {
            assertTrue(name, sandbox.get(name).isnil());
        }

        Globals standard = JsePlatform.standardGlobals();
        assertFalse(standard.get("io").isnil());
        assertFalse(standard.get("import").isnil());
        assertFalse(standard.get("require").isnil());
    }

    @Test
    public void standardGlobalsProvideEveryDocumentedRuntimeLibrary() {
        Globals globals = JsePlatform.standardGlobals();

        for (String name : new String[]{
            "io", "os", "package", "debug", "require", "luajava", "import"
        }) {
            assertFalse(name, globals.get(name).isnil());
        }
    }

    @Test
    public void toIntegerAcceptsFullWidthHexadecimalStrings() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
                "return tointeger('0xffffffffffffffff'), tointeger('0x8000000000000000'), " +
                "tointeger('18446744073709551615'), tointeger('0X2a'), " +
                "tointeger('ffffffffffffffff', 16), tointeger('-0x1'), tointeger('-1'), tointeger('z', 36)"
        ).invoke();

        assertEquals(-1L, result.arg1().tolong());
        assertEquals(Long.MIN_VALUE, result.arg(2).tolong());
        assertEquals(-1L, result.arg(3).tolong());
        assertEquals(42L, result.arg(4).tolong());
        assertEquals(-1L, result.arg(5).tolong());
        assertTrue(result.arg(6).isnil());
        assertEquals(-1L, result.arg(7).tolong());
        assertEquals(35L, result.arg(8).tolong());
    }

    @Test
    public void stringIntegerParsingUsesTheOfficialCoreRuntimePath() {
        LuaString string = LuaValue.valueOf("0xffffffffffffffff");
        LuaUtf8String utf8 = LuaUtf8String.valueOfString("ffffffffffffffff");
        LuaUtf8String base36 = LuaUtf8String.valueOfString("z");

        assertEquals(-1L, string.tointeger().tolong());
        assertEquals(-1L, utf8.tointeger(16).tolong());
        assertEquals(35L, base36.tointeger(36).tolong());
    }

    @Test
    public void overriddenStringClassesKeepCoreLuaStringSemantics() {
        LuaString string = LuaValue.valueOf("abcdef");
        LuaUtf8String utf8 = LuaUtf8String.valueOfString("LuaJ++");
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local value = 'abcdef'; local keys = {[value] = 'stored'}; " +
                "return #value, value:sub(2, 5), value .. '!', string.byte(value, 3), keys['abcdef']"
        ).invoke();

        assertEquals(6, string.rawlen());
        assertEquals("cde", string.substring(2, 5).tojstring());
        assertEquals(string.hashCode(), LuaValue.valueOf("abcdef").hashCode());
        assertEquals("LuaJ++", utf8.tojstring());
        assertEquals(6, result.arg1().toint());
        assertEquals("bcde", result.arg(2).tojstring());
        assertEquals("abcdef!", result.arg(3).tojstring());
        assertEquals((int) 'c', result.arg(4).toint());
        assertEquals("stored", result.arg(5).tojstring());
    }

    @Test
    public void luaStringUtf8ValidationAndLengthDoNotSkipAsciiOrValidMultibyteCharacters() {
        LuaString ascii = LuaValue.valueOf("abc");
        LuaString utf8 = LuaValue.valueOf("a中b");
        LuaString invalid = LuaString.valueOf(new byte[]{(byte) 0xc3, 0x28});
        LuaString overlong = LuaString.valueOf(new byte[]{(byte) 0xe0, (byte) 0x80, (byte) 0x80});
        LuaString surrogate = LuaString.valueOf(new byte[]{(byte) 0xed, (byte) 0xa0, (byte) 0x80});
        LuaString outsideUnicodeRange = LuaString.valueOf(
            new byte[]{(byte) 0xf4, (byte) 0x90, (byte) 0x80, (byte) 0x80}
        );
        LuaUtf8String utf8String = LuaUtf8String.valueOfString("a中b");
        LuaUtf8String invalidUtf8String = LuaUtf8String.valueOf(new int[]{0xd800});

        assertTrue(ascii.isValidUtf8());
        assertEquals(3, ascii.lengthAsUtf8());
        assertTrue(utf8.isValidUtf8());
        assertEquals(3, utf8.lengthAsUtf8());
        assertFalse(invalid.isValidUtf8());
        assertFalse(overlong.isValidUtf8());
        assertFalse(surrogate.isValidUtf8());
        assertFalse(outsideUnicodeRange.isValidUtf8());
        assertTrue(utf8String.isValidUtf8());
        assertFalse(invalidUtf8String.isValidUtf8());
    }

    @Test
    public void luaStringUtf8EncoderPreservesUnicodeSource() {
        String editorSource = "-- 中文注释\nlocal value = '中'\nreturn value\n";
        char[] source = editorSource.toCharArray();
        byte[] encoded = new byte[source.length * 3];
        int length = LuaString.encodeToUtf8(source, source.length, encoded, 0);

        assertEquals(editorSource, new String(encoded, 0, length, StandardCharsets.UTF_8));
    }

    @Test
    public void documentedImportSyntaxBindsTheSimpleClassName() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "import " + quote("java.lang.String") + "; return String('bridge').length()"
        ).invoke();

        assertEquals(6, result.arg1().toint());
    }

    @Test
    public void documentedImportAliasSyntaxBindsTheRequestedName() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "import Text " + quote("java.lang.String") + "; return Text('bridge').length()"
        ).invoke();

        assertEquals(6, result.arg1().toint());
    }

    @Test
    public void javaMembersRequireDotCalls() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local value = luajava.newInstance('java.lang.StringBuilder'); " +
                "value.append('ok'); " +
                "local dot = value.toString(); " +
                "local colonOk = pcall(function() return value:toString() end); " +
                "return dot, colonOk"
        ).invoke();

        assertEquals("ok", result.arg1().tojstring());
        assertFalse(result.arg(2).toboolean());
    }

    @Test
    public void popenHandlesAreClosable() {
        String command = System.getProperty("os.name").startsWith("Windows")
            ? "cmd /c echo luaj"
            : "printf luaj";
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local pipe = io.popen(" + quote(command) + ", 'r'); " +
                "local output = pipe:read('*a'); local closed = pipe:close(); return output, closed"
        ).invoke();

        assertEquals("luaj", result.arg1().tojstring().trim());
        assertTrue(result.arg(2).toboolean());
    }

    @Test(timeout = 10_000L)
    public void popenDrainsStderrBeforeReadingAllStandardOutput() {
        String command = "java -cp " + System.getProperty("java.class.path") + ' ' + StderrFlood.class.getName();
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local pipe = io.popen(" + quote(command) + ", 'r'); " +
                "local output = pipe:read('*a'); pipe:close(); return output"
        ).invoke();

        assertEquals("done", result.arg1().tojstring().trim());
    }

    @Test(timeout = 10_000L)
    public void popenWriteModeDrainsStandardOutputBeforeWritingAllInput() {
        String command = "java -cp " + System.getProperty("java.class.path") + ' ' + StdoutFloodReader.class.getName();
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local pipe = io.popen(" + quote(command) + ", 'w'); " +
                "pipe:write(string.rep('x', 128 * 1024)); return pipe:close()"
        ).invoke();

        assertTrue(result.arg1().toboolean());
    }

    @Test
    public void popenRejectsUnsafeReadWriteMode() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local ok, error = pcall(function() return io.popen('echo luaj', 'rw') end); return ok, error"
        ).invoke();

        assertFalse(result.arg1().toboolean());
        assertTrue(result.arg(2).tojstring().contains("not supported"));
    }

    @Test
    public void ioOpenKeepsRegularFileReadWriteBehavior() throws IOException {
        File file = File.createTempFile("luaj", ".txt");
        file.deleteOnExit();
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local file = io.open(" + quote(file.getAbsolutePath()) + ", 'w'); " +
                "file:write('bridge'); file:close(); " +
                "file = io.open(" + quote(file.getAbsolutePath()) + ", 'r'); " +
                "local value = file:read('*a'); local closed = file:close(); return value, closed"
        ).invoke();

        assertEquals("bridge", result.arg1().tojstring());
        assertTrue(result.arg(2).toboolean());
    }

    @Test
    public void classLookupKeepsSameNamesFromDifferentLoadersSeparate() throws Exception {
        byte[] bytecode = classBytes(LoaderFixture.class);
        String name = LoaderFixture.class.getName();
        ClassLoader firstLoader = new IsolatedClassLoader(name, bytecode);
        ClassLoader secondLoader = new IsolatedClassLoader(name, bytecode);

        JavaClass first = JavaClass.a(name, firstLoader);
        JavaClass second = JavaClass.a(name, secondLoader);

        assertNotSame(first, second);
        assertNotSame(first.touserdata(Class.class), second.touserdata(Class.class));
    }

    @Test
    public void luaJavaLookupUsesCurrentDynamicLoaderList() throws Exception {
        String originalName = LoaderFixture.class.getName();
        String name = originalName.replace("LoaderFixture", "LoaderIsolate");
        byte[] bytecode = renameClass(classBytes(LoaderFixture.class), originalName, name);
        ArrayList<ClassLoader> loaders = new ArrayList<>();
        LuajavaLib luajava = new LuajavaLib();

        loaders.add(new IsolatedClassLoader(name, bytecode));
        luajava.setClassLoaders(loaders);
        LuaValue first = luajava.bindClassForName(name);
        loaders.clear();
        loaders.add(new IsolatedClassLoader(name, bytecode));
        luajava.setClassLoaders(loaders);
        LuaValue second = luajava.bindClassForName(name);

        assertNotSame(first, second);
        assertNotSame(first.touserdata(Class.class), second.touserdata(Class.class));
    }

    @Test
    public void classLookupUsesOnlyTheLastPublishedLoaderSnapshot() throws Exception {
        String originalName = LoaderFixture.class.getName();
        String name = originalName.replace("LoaderFixture", "LoaderCapture");
        byte[] bytecode = renameClass(classBytes(LoaderFixture.class), originalName, name);
        ArrayList<ClassLoader> loaders = new ArrayList<>();
        LuajavaLib luajava = new LuajavaLib();

        loaders.add(new IsolatedClassLoader(name, bytecode));
        luajava.setClassLoaders(loaders);
        LuaValue published = luajava.bindClassForName(name);

        loaders.clear();
        loaders.add(new IsolatedClassLoader(name, bytecode));
        LuaValue stillPublished = luajava.bindClassForName(name);

        luajava.setClassLoaders(loaders);
        LuaValue republished = luajava.bindClassForName(name);

        assertSame(published, stillPublished);
        assertNotSame(published, republished);
    }

    @Test
    public void legacyPublicJseApiRemainsInstantiableAndWritable() {
        JsePlatform platform = new JsePlatform();
        LuajavaLib luajava = new LuajavaLib();
        HashMap<String, LuaValue> legacyCache = new HashMap<>();

        luajava.f = legacyCache;

        assertNotSame(null, platform);
        assertEquals(legacyCache, luajava.f);
    }

    @Test
    public void bindClassForNameKeepsItsLegacyRuntimeException() {
        LuajavaLib luajava = new LuajavaLib();

        try {
            luajava.bindClassForName("missing.bridge.Class");
        } catch (Exception expected) {
            assertTrue(expected instanceof ClassNotFoundException);
            assertEquals("missing.bridge.Class", expected.getMessage());
            return;
        }
        throw new AssertionError("expected ClassNotFoundException");
    }

    @Test
    public void importOfMissingClassRaisesLuaError() {
        Globals globals = JsePlatform.standardGlobals();

        Varargs result = globals.load(
            "local ok, error = pcall(function() import 'missing.bridge.Class' end); return ok, tostring(error)"
        ).invoke();

        assertFalse(result.arg1().toboolean());
        assertTrue(result.arg(2).tojstring().contains("missing.bridge.Class"));
    }

    @Test
    public void boundJavaMethodsAreCachedAndInvokeCorrectly() {
        JavaInstance instance = new JavaInstance(new Counter());
        LuaValue first = instance.get("increment");
        LuaValue second = instance.get("increment");

        assertSame(first, second);
        assertEquals(3, first.call(LuaValue.valueOf(3)).toint());
        assertEquals(5, second.call(LuaValue.valueOf(2)).toint());
    }

    @Test
    public void collectionIterationKeepsOrderingAndObservesLaterMutations() {
        ArrayList<String> list = new ArrayList<>();
        list.add("first");
        JavaInstance listValue = new JavaInstance(list);
        Varargs firstListItem = listValue.next(LuaValue.NIL);
        list.add("second");
        Varargs secondListItem = listValue.next(firstListItem.arg1());

        assertEquals(0, firstListItem.arg1().toint());
        assertEquals("first", firstListItem.arg(2).tojstring());
        assertEquals(1, secondListItem.arg1().toint());
        assertEquals("second", secondListItem.arg(2).tojstring());
        assertTrue(listValue.next(secondListItem.arg1()).isnil(1));

        LinkedHashMap<String, Integer> map = new LinkedHashMap<>();
        map.put("first", 1);
        JavaInstance mapValue = new JavaInstance(map);
        Varargs firstMapItem = mapValue.next(LuaValue.NIL);
        map.put("second", 2);
        Varargs secondMapItem = mapValue.next(firstMapItem.arg1());

        assertEquals("first", firstMapItem.arg1().tojstring());
        assertEquals(1, firstMapItem.arg(2).toint());
        assertEquals("second", secondMapItem.arg1().tojstring());
        assertEquals(2, secondMapItem.arg(2).toint());

        LinkedHashSet<String> set = new LinkedHashSet<>();
        set.add("first");
        JavaInstance setValue = new JavaInstance(set);
        Varargs firstSetItem = setValue.next(LuaValue.NIL);
        set.add("second");
        Varargs secondSetItem = setValue.next(firstSetItem.arg1());

        assertEquals(0, firstSetItem.arg1().toint());
        assertEquals("first", firstSetItem.arg(2).tojstring());
        assertEquals(1, secondSetItem.arg1().toint());
        assertEquals("second", secondSetItem.arg(2).tojstring());
    }

    @Test
    public void collectionLengthIncludesSets() {
        Globals globals = JsePlatform.standardGlobals();
        LinkedHashSet<String> set = new LinkedHashSet<>();
        set.add("first");
        set.add("second");
        globals.set("set", CoerceJavaToLua.coerce(set));

        assertEquals(2, globals.load("return #set").call().toint());
    }

    @Test
    public void recursiveTableConversionPreservesContainerCycles() {
        ArrayList<Object> list = new ArrayList<>();
        list.add(list);
        LinkedHashMap<String, Object> map = new LinkedHashMap<>();
        map.put("self", map);
        list.add(map);

        LuaValue convertedList = LuajavaLib.asTable(list, true);
        LuaValue convertedMap = convertedList.get(2);

        assertSame(convertedList, convertedList.get(1));
        assertSame(convertedMap, convertedMap.get("self"));
    }

    @Test
    public void packageLookupUsesTheLatestDynamicLoaderSnapshot() throws Exception {
        String originalName = LoaderFixture.class.getName();
        String name = originalName.replace("LoaderFixture", "LoaderPackage");
        byte[] bytecode = renameClass(classBytes(LoaderFixture.class), originalName, name);
        LuajavaLib luajava = new LuajavaLib();
        JavaPackage packageRoot = new JavaPackage("org", luajava);
        LuaValue packageNode = packageRoot.get("luaj").get("lib").get("jse");
        LuaValue unresolved = packageNode.get("JseBridgeTest$LoaderPackage");

        assertTrue(unresolved instanceof JavaPackage);
        assertNotSame(unresolved, packageNode.get("JseBridgeTest$LoaderPackage"));

        ArrayList<ClassLoader> loaders = new ArrayList<>();
        loaders.add(new IsolatedClassLoader(name, bytecode));
        luajava.setClassLoaders(loaders);
        LuaValue resolved = packageNode.get("JseBridgeTest$LoaderPackage");

        assertTrue(resolved instanceof JavaClass);
        assertEquals(name, resolved.touserdata(Class.class).getName());
    }

    @Test
    public void explicitConstructorAndMethodSelectionBypassOverloadScoring() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local constructor = luajava.constructor(" + quote(className) + ", {'long'}); " +
                "local value = constructor(1); " +
                "local method = luajava.method(value, 'select', {'long'}); " +
                "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "local static = luajava.method(Fixture, 'staticSelect', {'int'}); " +
                "return value.kind, method(1), static(1)"
        ).invoke();

        assertEquals("long", result.arg1().tojstring());
        assertEquals("long", result.arg(2).tojstring());
        assertEquals("static-int", result.arg(3).tojstring());
    }

    @Test
    public void explicitMethodSelectionAcceptsJavaClassAndArrayClassParameters() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local String = luajava.bindClass('java.lang.String'); " +
                "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "local StringArray = String.array({}).class; " +
                "local arrayLength = luajava.method(Fixture, 'arrayLength', {StringArray}); " +
                "return arrayLength(String.array({'one', 'two'}))"
        ).invoke();

        assertEquals(2, result.arg1().toint());
    }

    @Test
    public void automaticOverloadSelectionKeepsFullWidthLuaIntegersAsLongs() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "return Fixture.automaticSelect(tointeger('0x100000000'))"
        ).invoke();

        assertEquals("automatic-long", result.arg1().tojstring());
    }

    @Test
    public void automaticOverloadSelectionUsesLongForFullWidthConstructorsAndMethods() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "local value = Fixture(tointeger('0x100000000')); " +
                "return value.kind, value.select(tointeger('0x100000000'))"
        ).invoke();

        assertEquals("long", result.arg1().tojstring());
        assertEquals("long", result.arg(2).tojstring());
    }

    @Test
    public void automaticOverloadSelectionDoesNotTruncateFullWidthLuaIntegersForNarrowTypes() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "return Fixture.narrowOrLong(tointeger('0x100000000'))"
        ).invoke();

        assertEquals("long", result.arg1().tojstring());
    }

    @Test
    public void explicitSignaturesResolveAmbiguousNilInterfaceVarargAndArrayCalls() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "local nullable = luajava.method(Fixture, 'nullable', {'java.lang.String'}); " +
                "local interface = luajava.method(Fixture, 'interfaceKind', {'java.lang.Runnable'}); " +
                "local fixed = luajava.method(Fixture, 'fixedOrVararg', {'java.lang.String'}); " +
                "local vararg = luajava.method(Fixture, 'fixedOrVararg', {'java.lang.String[]'}); " +
                "local array = luajava.method(Fixture, 'arrayLength', {'java.lang.String[]'}); " +
                "return nullable(nil), interface({run = function() end}), fixed('one'), vararg({'one', 'two'}), array({'one', 'two'}), array({})"
        ).invoke();

        assertEquals("string-null", result.arg1().tojstring());
        assertEquals("runnable", result.arg(2).tojstring());
        assertEquals("fixed:one", result.arg(3).tojstring());
        assertEquals("vararg:2", result.arg(4).tojstring());
        assertEquals(2, result.arg(5).toint());
        assertEquals(0, result.arg(6).toint());
    }

    @Test
    public void explicitBoundMethodPreservesThreeArguments() {
        Globals globals = JsePlatform.standardGlobals();
        String className = SelectionFixture.class.getName();
        Varargs result = globals.load(
            "local Fixture = luajava.bindClass(" + quote(className) + "); " +
                "local method = luajava.method(Fixture, 'joinThree', {'int', 'int', 'int'}); " +
                "return method(1, 2, 3)"
        ).invoke();

        assertEquals("1:2:3", result.arg1().tojstring());
    }

    @Test
    public void javaIteratorSupportsMapsArraysIteratorsAndKotlinSequences() {
        Globals globals = JsePlatform.standardGlobals();
        LinkedHashMap<String, Integer> map = new LinkedHashMap<>();
        map.put("first", 1);
        map.put("second", 2);
        ArrayList<String> iteratorSource = new ArrayList<>();
        iteratorSource.add("iterator");
        globals.set("map", CoerceJavaToLua.coerce(map));
        globals.set("array", CoerceJavaToLua.coerce(new String[]{"array"}));
        globals.set("iterator", CoerceJavaToLua.coerce(iteratorSource.iterator()));

        Varargs result = globals.load(
            "local mapValues = {}; " +
                "for key, value in luajava.iterate(map) do mapValues[key] = value end; " +
                "local _, arrayValue = luajava.iterate(array)(); " +
                "local _, iteratorValue = luajava.iterate(iterator)(); " +
                "local sequence = luajava.kotlinObject(" + quote(KotlinObjectFixture.class.getName()) + ").sequence(); " +
                "local sequenceValues = {}; " +
                "for _, value in luajava.iterate(sequence) do table.insert(sequenceValues, value) end; " +
                "return mapValues.first, mapValues.second, arrayValue, iteratorValue, sequenceValues[1], sequenceValues[2]"
        ).invoke();

        assertEquals(1, result.arg1().toint());
        assertEquals(2, result.arg(2).toint());
        assertEquals("array", result.arg(3).tojstring());
        assertEquals("iterator", result.arg(4).tojstring());
        assertEquals("first", result.arg(5).tojstring());
        assertEquals("second", result.arg(6).tojstring());
    }

    @Test
    public void collectionKeysDoNotPopulateSharedMemberDispatchCaches() {
        JavaInstance mapValue = new JavaInstance(new HashMap<>());

        for (int index = 0; index < 100; index++) {
            LuaValue key = new JavaInstance(new Object());
            mapValue.set(key, LuaValue.valueOf(index));
            assertEquals(index, mapValue.get(key).toint());
        }

        assertTrue(mapValue.f.m.isEmpty());
        assertTrue(mapValue.f.n.isEmpty());
        assertTrue(mapValue.f.o.isEmpty());
    }

    @Test
    public void coercionDoesNotCacheDynamicTargetClasses() throws Exception {
        byte[] bytecode = classBytes(LoaderFixture.class);
        String name = LoaderFixture.class.getName();
        Class<?> first = new IsolatedClassLoader(name, bytecode).loadClass(name);
        Class<?> second = new IsolatedClassLoader(name, bytecode).loadClass(name);
        Class<?> array = Array.newInstance(first, 0).getClass();
        int fixedCacheSize = CoerceLuaToJava.f.size();

        assertNull(CoerceLuaToJava.coerce(LuaValue.NIL, first));
        assertNull(CoerceLuaToJava.coerce(LuaValue.NIL, second));
        assertNull(CoerceLuaToJava.coerce(LuaValue.NIL, array));

        assertEquals(fixedCacheSize, CoerceLuaToJava.f.size());
        assertFalse(CoerceLuaToJava.f.containsKey(first));
        assertFalse(CoerceLuaToJava.f.containsKey(second));
        assertFalse(CoerceLuaToJava.f.containsKey(array));
    }

    @Test
    public void coercionPreservesPrimitiveArrayAndCollectionConversions() {
        Globals globals = JsePlatform.standardGlobals();
        LuaValue numbers = globals.load("return {1, 2}").call();
        LuaValue values = globals.load("return {one = 1, two = 2, 'first', 'second'}").call();

        assertEquals("first", values.get(1).tojstring());
        assertEquals("second", values.get(2).tojstring());
        assertEquals(LuaValue.TNUMBER, values.get("one").type());
        int[] array = (int[]) CoerceLuaToJava.coerce(numbers, int[].class);
        Map<?, ?> map = (Map<?, ?>) CoerceLuaToJava.coerce(values, Map.class);
        ArrayList<?> list = (ArrayList<?>) CoerceLuaToJava.coerce(values, ArrayList.class);

        assertEquals(1, array[0]);
        assertEquals(2, array[1]);
        assertEquals(Double.class, CoerceLuaToJava.coerce(values.get("one"), Object.class).getClass());
        assertEquals(1.0, map.get("one"));
        assertEquals(2.0, map.get("two"));
        assertEquals("first", list.get(0));
        assertEquals("second", list.get(1));
    }

    @Test
    public void luaValuesAreReturnedWithoutAdditionalWrapping() {
        LuaValue value = LuaValue.valueOf("value");
        JavaInstance instance = new JavaInstance(new Counter());

        assertSame(value, CoerceJavaToLua.coerce(value));
        assertSame(instance, CoerceJavaToLua.coerce(instance));
    }

    @Test
    public void coercionCacheSupportsConcurrentWorkerCallbacks() throws Exception {
        int workerCount = 8;
        CountDownLatch ready = new CountDownLatch(workerCount);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch complete = new CountDownLatch(workerCount);
        AtomicReference<Throwable> failure = new AtomicReference<>();

        for (int worker = 0; worker < workerCount; worker++) {
            Thread thread = new Thread(() -> {
                ready.countDown();
                try {
                    start.await();
                    for (int index = 0; index < 1_000; index++) {
                        assertEquals(index, CoerceJavaToLua.coerce(index).toint());
                        assertEquals("value", CoerceJavaToLua.coerce("value").tojstring());
                        assertSame(LuaValue.TRUE, CoerceJavaToLua.coerce(LuaValue.TRUE));
                        assertTrue(CoerceJavaToLua.coerce(new Counter()).isuserdata(Counter.class));
                    }
                } catch (Throwable throwable) {
                    failure.compareAndSet(null, throwable);
                } finally {
                    complete.countDown();
                }
            });
            thread.start();
        }

        ready.await();
        start.countDown();
        complete.await();
        if (failure.get() != null) {
            throw new AssertionError("concurrent coercion failed", failure.get());
        }
    }

    @Test
    public void constructorLookupSkipsClassesWithoutPublicConstructors() {
        assertNull(JavaClass.a(NoPublicConstructor.class).getConstructor());

        LuaValue constructor = JavaClass.a(PublicConstructors.class).getConstructor();
        JavaInstance withoutArg = (JavaInstance) constructor.invoke(LuaValue.NONE).arg1();
        JavaInstance withArg = (JavaInstance) constructor.invoke(LuaValue.valueOf("named")).arg1();

        assertEquals("default", ((PublicConstructors) withoutArg.touserdata()).value);
        assertEquals("named", ((PublicConstructors) withArg.touserdata()).value);
    }

    @Test
    public void luaCanAccessKotlinObjectsCompanionsAndJvmStaticMethods() {
        Globals globals = JsePlatform.standardGlobals();
        String objectName = KotlinObjectFixture.class.getName();
        String companionName = KotlinCompanionFixture.class.getName();
        Varargs result = globals.load(
            "local object = luajava.kotlinObject(" + quote(objectName) + "); " +
                "local companion = luajava.kotlinCompanion(" + quote(companionName) + "); " +
                "local klass = luajava.bindClass(" + quote(companionName) + "); " +
                "return object.greet('lua'), object.label, companion.greet('lua'), companion.label, klass.staticGreet('lua')"
        ).invoke();

        assertEquals("object:lua", result.arg1().tojstring());
        assertEquals("object", result.arg(2).tojstring());
        assertEquals("companion:lua", result.arg(3).tojstring());
        assertEquals("companion", result.arg(4).tojstring());
        assertEquals("static:lua", result.arg(5).tojstring());
    }

    @Test
    public void kotlinInteropHelpersRejectMissingGeneratedMembers() {
        Globals globals = JsePlatform.standardGlobals();

        Varargs result = globals.load(
            "local ok, error = pcall(function() return luajava.kotlinObject('java.lang.String') end); return ok, error"
        ).invoke();

        assertFalse(result.arg1().toboolean());
        assertTrue(result.arg(2).tojstring().contains("Kotlin object"));
    }

    @Test
    public void luaConvenienceCollectionConversionsKeepExpectedValues() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local list = luajava.toList({'first', 'second'}); " +
                "local set = luajava.toSet({'first', 'second', 'first'}); " +
                "local map = luajava.toMap({first = 1, second = 'two'}); " +
                "local table = luajava.toTable(list); " +
                "return list[0], list[1], set.contains('second'), set.size(), map['first'], map['second'], table[1], table[2], rawequal(table, luajava.toTable(table))"
        ).invoke();

        assertEquals("first", result.arg1().tojstring());
        assertEquals("second", result.arg(2).tojstring());
        assertTrue(result.arg(3).toboolean());
        assertEquals(2, result.arg(4).toint());
        assertEquals(1, result.arg(5).toint());
        assertEquals("two", result.arg(6).tojstring());
        assertEquals("first", result.arg(7).tojstring());
        assertEquals("second", result.arg(8).tojstring());
        assertTrue(result.arg(9).toboolean());
    }

    @Test
    public void toTableUsesShallowConversionUnlessRecursionIsRequested() {
        Globals globals = JsePlatform.standardGlobals();
        Varargs result = globals.load(
            "local list = luajava.toList({'nested'}); " +
                "local outer = luajava.toList({list}); " +
                "local shallow = luajava.toTable(outer); " +
                "local recursive = luajava.toTable(outer, true); " +
                "return shallow[1].class.name, recursive[1][1]"
        ).invoke();

        assertEquals("java.util.ArrayList", result.arg1().tojstring());
        assertEquals("nested", result.arg(2).tojstring());
    }

    private static String quote(String value) {
        return '"' + value.replace("\\", "\\\\").replace("\"", "\\\"") + '"';
    }

    private static byte[] classBytes(Class<?> type) throws IOException {
        String resourceName = '/' + type.getName().replace('.', '/') + ".class";
        try (InputStream input = type.getResourceAsStream(resourceName);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            if (input == null) {
                throw new IOException("missing class resource " + resourceName);
            }
            byte[] buffer = new byte[4096];
            for (int count; (count = input.read(buffer)) != -1; ) {
                output.write(buffer, 0, count);
            }
            return output.toByteArray();
        }
    }

    private static byte[] renameClass(byte[] bytecode, String originalName, String newName) {
        byte[] original = originalName.replace('.', '/').getBytes(StandardCharsets.US_ASCII);
        byte[] replacement = newName.replace('.', '/').getBytes(StandardCharsets.US_ASCII);
        if (original.length != replacement.length) {
            throw new IllegalArgumentException("class names must have equal lengths");
        }

        byte[] renamed = bytecode.clone();
        for (int index = 0; index <= renamed.length - original.length; index++) {
            boolean matches = true;
            for (int offset = 0; offset < original.length; offset++) {
                if (renamed[index + offset] != original[offset]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                System.arraycopy(replacement, 0, renamed, index, replacement.length);
                index += replacement.length - 1;
            }
        }
        return renamed;
    }

    public static final class User {
        public final int id;

        public User(int id) {
            this.id = id;
        }
    }

    public static final class Counter {
        private int value;

        public int increment(int amount) {
            value += amount;
            return value;
        }
    }

    public static final class SelectionFixture {
        public final String kind;

        public SelectionFixture(int value) {
            kind = "int";
        }

        public SelectionFixture(long value) {
            kind = "long";
        }

        public String select(int value) {
            return "int";
        }

        public String select(long value) {
            return "long";
        }

        public static String staticSelect(int value) {
            return "static-int";
        }

        public static String joinThree(int first, int second, int third) {
            return first + ":" + second + ":" + third;
        }

        public static String automaticSelect(int value) {
            return "automatic-int";
        }

        public static String automaticSelect(long value) {
            return "automatic-long";
        }

        public static String narrowOrLong(byte value) {
            return "byte";
        }

        public static String narrowOrLong(short value) {
            return "short";
        }

        public static String narrowOrLong(char value) {
            return "char";
        }

        public static String narrowOrLong(int value) {
            return "int";
        }

        public static String narrowOrLong(long value) {
            return "long";
        }

        public static String nullable(String value) {
            return value == null ? "string-null" : value;
        }

        public static String nullable(StringBuilder value) {
            return value == null ? "builder-null" : value.toString();
        }

        public static String interfaceKind(Runnable value) {
            return "runnable";
        }

        public static String interfaceKind(AutoCloseable value) {
            return "closeable";
        }

        public static String fixedOrVararg(String value) {
            return "fixed:" + value;
        }

        public static String fixedOrVararg(String... values) {
            return "vararg:" + values.length;
        }

        public static int arrayLength(String[] values) {
            return values.length;
        }
    }

    public static final class PublicConstructors {
        final String value;

        public PublicConstructors() {
            value = "default";
        }

        public PublicConstructors(String value) {
            this.value = value;
        }
    }

    private static final class NoPublicConstructor {
        private NoPublicConstructor() {
        }
    }

    private static final class IsolatedClassLoader extends ClassLoader {
        private final String targetName;
        private final byte[] targetBytecode;

        private IsolatedClassLoader(String targetName, byte[] targetBytecode) {
            super(JseBridgeTest.class.getClassLoader());
            this.targetName = targetName;
            this.targetBytecode = targetBytecode;
        }

        @Override
        protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
            synchronized (this) {
                if (targetName.equals(name)) {
                    Class<?> loaded = findLoadedClass(name);
                    if (loaded == null) {
                        loaded = defineClass(name, targetBytecode, 0, targetBytecode.length);
                    }
                    if (resolve) {
                        resolveClass(loaded);
                    }
                    return loaded;
                }
                return super.loadClass(name, resolve);
            }
        }
    }

    public static final class LoaderFixture {
    }

    public static final class StderrFlood {
        public static void main(String[] args) {
            byte[] bytes = new byte[128 * 1024];
            Arrays.fill(bytes, (byte) 'x');
            System.err.write(bytes, 0, bytes.length);
            System.err.flush();
            System.out.println("done");
        }
    }

    public static final class StdoutFloodReader {
        public static void main(String[] args) throws IOException {
            byte[] bytes = new byte[128 * 1024];
            Arrays.fill(bytes, (byte) 'x');
            System.out.write(bytes, 0, bytes.length);
            System.out.flush();
            while (System.in.read(bytes) != -1) {
                // Consume all stdin so a write-mode popen can finish cleanly.
            }
        }
    }
}

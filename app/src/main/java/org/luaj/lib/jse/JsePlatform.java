package org.luaj.lib.jse;

import org.luaj.Globals;
import org.luaj.LoadState;
import org.luaj.LuaValue;
import org.luaj.compiler.LuaC;
import org.luaj.lib.BaseLib;
import org.luaj.lib.Bit32Lib;
import org.luaj.lib.CoroutineLib;
import org.luaj.lib.DebugLib;
import org.luaj.lib.PackageLib;
import org.luaj.lib.StringLib;
import org.luaj.lib.TableLib;
import org.luaj.lib.Utf8Lib;

import java.util.ArrayList;

/**
 * Factory methods for normal JSE globals and restricted Lua execution globals.
 */
public class JsePlatform {
    public JsePlatform() {
    }

    public static Globals standardGlobals() {
        Globals globals = new Globals();
        globals.load(new JseBaseLib());
        globals.load(new PackageLib());
        globals.load(new Bit32Lib());
        globals.load(new TableLib());
        globals.load(new StringLib());
        globals.load(new CoroutineLib());
        globals.load(new JseMathLib());
        globals.load(new JseIoLib());
        globals.load(new JseOsLib());
        globals.load(new LuajavaLib());
        globals.load(new DebugLib());
        globals.load(new Utf8Lib());
        installCompiler(globals);
        return globals;
    }

    public static Globals debugGlobals() {
        Globals globals = standardGlobals();
        globals.load(new DebugLib());
        return globals;
    }

    /**
     * Creates globals for untrusted snippets without filesystem, process, package, debug, or Java bridges.
     */
    public static Globals sandboxGlobals() {
        Globals globals = new Globals();
        globals.load(new BaseLib());
        globals.load(new Bit32Lib());
        globals.load(new TableLib());
        globals.load(new StringLib());
        globals.load(new CoroutineLib());
        globals.load(new JseMathLib());
        globals.load(new Utf8Lib());
        installCompiler(globals);

        // BaseLib exposes file loaders even when no JSE filesystem library was installed.
        for (String name : new String[]{
            "dofile", "loadfile", "collectgarbage", "gcinfo", "newproxy", "module", "require",
            "io", "os", "package", "debug", "luajava", "import"
        }) {
            globals.set(name, LuaValue.NIL);
        }
        return globals;
    }

    /**
     * Publishes the current LuaDexLoader class loader list to normal globals.
     */
    public static void publishClassLoaders(Globals globals, ArrayList<ClassLoader> classLoaders) {
        if (globals.s == null) {
            throw new IllegalStateException("LuaJava is not installed in these globals");
        }
        globals.s.setClassLoaders(classLoaders);
    }

    public static void luaMain(LuaValue mainChunk, String[] args) {
        Globals globals = standardGlobals();
        LuaValue[] values = new LuaValue[args.length];
        for (int index = 0; index < args.length; index++) {
            values[index] = LuaValue.valueOf(args[index]);
        }
        LuaValue arg = LuaValue.listOf(values);
        arg.set("n", args.length);
        globals.set("arg", arg);
        mainChunk.initupvalue1(globals);
        mainChunk.invoke(LuaValue.varargsOf(values));
    }

    private static void installCompiler(Globals globals) {
        LoadState.install(globals);
        LuaC.install(globals);
    }
}

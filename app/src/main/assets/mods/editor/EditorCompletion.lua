--- 编辑器补全词表。在后台线程收集，不参与打开或保存文件。
local _M = {}

function _M.install(editor)
    thread(function(target, bindClass)
        local LuaActivity = bindClass "com.androlua.LuaActivity"
        local methods, seen = {}, {}
        for _, method in (LuaActivity.getMethods()) do
            local name = tostring(method.getName())
            if not name:find("%$") and not seen[name] then
                seen[name] = true
                methods[#methods + 1] = name .. "()"
            end
        end
        methods[#methods + 1] = "themeUtil"
        ClassesNames.ensure()
        local classes = ClassesNames.simple_top_classes
        local names = {
            "onKeyDown", "onKeyUp", "onKeyLongPress", "onKeyShortcut",
            "onCreate", "onStart", "onResume",
            "onPause", "onStop", "onDestroy", "onError", "onReceive",
            "onActivityResult", "onResult", "onNightModeChanged",
            "onContentChanged", "onConfigurationChanged",
            "onContextItemSelected", "onCreateContextMenu",
            "onCreateOptionsMenu", "onOptionsItemSelected", "onRequestPermissionsResult",
            "onClick", "onTouch", "onLongClick", "onPanelClosed",
            "onSupportActionModeStarted", "onSupportActionModeFinished",
            "onItemClick", "onItemLongClick", "onVersionChanged", "this", "android"
        }
        local base = #names
        if classes then
            for index = 0, #classes - 1 do
                names[base + index + 1] = classes[index]
            end
        end
        target.addNames(names)
            .addNames({ "byte", "boolean", "short", "int", "long", "float", "double", "char" })
            .addNames({ "R", "dump", "toutf8", "loadlayout", "printf", "thread", "xTask", "lazy" })
            .addPackage("activity", methods)
            .addPackage("this", methods)
            .addPackage("debug", { "debug", "gethook", "getinfo", "getlocal", "getmetatable", "getregistry", "getupvalue", "getuservalue", "sethook", "setlocal", "setmetatable", "setupvalue", "setuservalue", "traceback", "upvalueid", "upvaluejoin" })
            .addPackage("coroutine", { "create", "resume", "running", "status", "wrap", "yield" })
            .addPackage("math", { "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log", "max", "min", "modf", "pi", "pow", "rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh" })
            .addPackage("string", { "byte", "char", "dump", "find", "format", "gfind", "gmatch", "gsub", "len", "lower", "match", "pack", "rep", "reverse", "sub", "toutf8", "unpack", "upper" })
            .addPackage("utf8", { "byte", "char", "find", "format", "gfind", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper" })
            .addPackage("bit32", { "arshift", "band", "bnot", "bor", "btest", "bxor", "extract", "lrotate", "lshift", "replace", "rrotate", "rshift" })
            .addPackage("table", { "add", "clear", "clone", "concat", "const", "copy", "dump", "find", "foreach", "foreachi", "gfind", "insert", "pack", "remove", "size", "sort", "sub", "unpack" })
            .addPackage("os", { "clock", "date", "difftime", "execute", "exit", "getenv", "remove", "rename", "setlocale", "time", "tmpname" })
            .addPackage("file", { "exists", "info", "list", "mkdir", "readall", "save", "type" })
            .addPackage("json", { "decode", "encode" })
            .addPackage("okHttp", { "get", "unsafe", "post", "postText", "postJson" })
            .addPackage("okhttp", { "delete", "get", "head", "post", "postJson", "put" })
            .addPackage("ext", { "pack", "packsize", "unpack" })
            .addPackage("res", { "bitmap", "color", "dimen", "drawable", "font", "layout", "language", "plurals", "raw", "string", "view" })
            .addPackage("saf", { "delete", "exists", "list", "mkdir", "read", "rename", "save", "type" })
            .addPackage("luajava", { "astable", "bindClass", "constructor", "createProxy", "instanceof", "iterate", "kotlinCompanion", "kotlinObject", "loadLib", "method", "new", "newInstance", "toList", "toMap", "toSet", "toTable" })
            .addPackage("io", { "close", "flush", "input", "lines", "open", "output", "popen", "read", "tmpfile", "type", "write" })
    end, editor, bindClass)
end

return _M

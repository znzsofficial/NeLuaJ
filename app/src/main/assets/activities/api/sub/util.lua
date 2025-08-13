local insert = table.insert
local string_format = string.format
local table_foreach = table.foreach

function assignClass(str)
    local eee = {
        aa = {}, --父类继承
        bb = {}, --构建方法
        cc = {}, --公有方法
        dd = {}, --公有事件
        ee = {}, --公有字段
        ff = {}, --公有setter
        gg = {}, --公有getter
        hh = {}, --R类资源
    }
    local class = bindClass(str)
    local super = class.getSuperclass()
    super = super and " 父类 " .. tostring(super.getName())
    table.insert(eee.aa, super)
    for i = 0, #class.getClasses() - 1 do
        table.insert(eee.aa, tostring(class.getClasses()[i]))
    end

    --构建方法
    for i = 0, #class.getConstructors() - 1 do
        local aa = tostring(class.getConstructors()[i])
        local a, b = aa:find("throws")
        if a then
            aa = aa:sub(1, a - 2)
        end
        insert(eee.bb, aa)
    end

    --公有字段
    for i = 0, #class.getFields() - 1 do
        local a = tostring(class.getFields()[i])
        insert(eee.ee, a)
    end

    getf = class.getMethods()

    for n = 0, #getf - 1 do
        local aa, str = pcall(function()
            local str = tostring(getf[n])
            return str
        end)
        if not aa then
            continue
        end

        if str:find("throws") then
            local a, _ = str:find("()%)")
            str = str:sub(1, a)
        end

        if ex == "java.lang.Object" then
            insert(eee.cc, str)
        else
            if not str:find("Object%.") then
                insert(eee.cc, str)
            end
        end

        local e1 = str:match("%.setOn(%a+)Listener")
        local s1, s2 = str:match("%.set(%a+)(%([%a$%.]+%))")
        local g1, g2 = str:match("([%a$%.]+) [%a$%.]+%.get(%a+)%(%)")
        if e1 then
            insert(eee.dd, "on" .. e1)
        elseif s1 then
            insert(eee.ff, s1 .. s2)
        end
        if g1 then
            insert(eee.gg, string_format("(%s)%s", g1, g2))
        end
    end
    return eee, class
end

local dumplua_closure = [[
local closures = {}
local function closure(t) 
  closures[#closures+1] = t
  t[1] = assert(loadstring(t[1]))
  return t[1]
end

for _,t in pairs(closures) do
  for i = 2,#t do 
    debug.setupvalue(t[1], i-1, t[i]) 
  end 
end
]]

local lua_reserved_keywords = {
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
    'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
    'return', 'then', 'true', 'until', 'while' }

local function keys(t)
    local res = {}
    local oktypes = { stringstring = true, numbernumber = true }
    local function cmpfct(a, b)
        if oktypes[type(a) .. type(b)] then
            return a < b
        else
            return type(a) < type(b)
        end
    end
    for k in pairs(t) do
        res[#res + 1] = k
    end
    table.sort(res, cmpfct)
    return res
end

local c_functions = {}
for _, lib in pairs { '_G', 'string', 'table', 'math',
                      'coroutine', 'package', 'debug' } do
    local t = _G[lib] or {}
    lib = lib .. "."
    if lib == "_G." then
        lib = ""
    end
    for k, v in pairs(t) do
        if type(v) == 'function' and not pcall(string.dump, v) then
            c_functions[v] = lib .. k
        end
    end
end

function dump(value, varname, fastmode, ident)
    local defined, dumplua = {}
    -- Local variables for speed optimization
    local string_format, type, string_dump, string_rep = string.format, type, string.dump, string.rep
    local tostring, pairs, table_concat = tostring, pairs, table.concat
    local keycache, strvalcache, out, closure_cnt = {}, {}, {}, 0
    setmetatable(strvalcache, { __index = function(t, value)
        local res = string_format('%q', value)
        t[value] = res
        return res
    end })
    local fcts = {
        string = function(value)
            return strvalcache[value]
        end,
        number = function(value)
            return value
        end,
        boolean = function(value)
            return tostring(value)
        end,
        ['nil'] = function(value)
            return 'nil'
        end,
        ['function'] = function(value)
            return string_format("loadstring(%q)", string_dump(value))
        end,
        userdata = function(value)
            -- find the variable name
            local var
            local i = 1
            while true do
                local n, v = debug.getlocal(3, i)
                if not n then
                    break
                end
                if n == "subpath" then
                    var = v
                end
                --print(n,v)
                i = i + 1
            end

            error("Cannot dump userdata (" .. tostring(value) .. " - " .. (var or "unknown") .. ")")
        end,
        thread = function()
            error("Cannot dump threads")
        end,
    }
    local function test_defined(value, path)
        if defined[value] then
            if path:match("^getmetatable.*%)$") then
                out[#out + 1] = string_format("s%s, %s)\n", path:sub(2, -2), defined[value])
            else
                out[#out + 1] = path .. " = " .. defined[value] .. "\n"
            end
            return true
        end
        defined[value] = path
    end
    local function make_key(t, key)
        local s
        if type(key) == 'string' and key:match('^[_%a][_%w]*$') then
            s = key .. "="
        else
            s = "[" .. dumplua(key, 0) .. "]="
        end
        t[key] = s
        return s
    end
    for _, k in ipairs(lua_reserved_keywords) do
        keycache[k] = '["' .. k .. '"] = '
    end
    if fastmode then
        fcts.table = function(value)
            -- Table value
            local numidx = 1
            out[#out + 1] = "{"
            for key, val in pairs(value) do
                if key == numidx then
                    numidx = numidx + 1
                else
                    out[#out + 1] = keycache[key]
                end
                local str = dumplua(val)
                out[#out + 1] = str .. ","
            end
            if string.sub(out[#out], -1) == "," then
                out[#out] = string.sub(out[#out], 1, -2);
            end
            out[#out + 1] = "}"
            return ""
        end
    else
        fcts.table = function(value, ident, path)
            if test_defined(value, path) then
                return "nil"
            end
            -- Table value
            local sep, str, numidx, totallen = " ", {}, 1, 0
            local meta, metastr = (debug or getfenv()).getmetatable(value)
            if meta then
                ident = ident + 1
                metastr = dumplua(meta, ident, "getmetatable(" .. path .. ")")
                totallen = totallen + #metastr + 16
            end
            for _, key in pairs(keys(value)) do
                local val = value[key]
                local s = ""
                local subpath = path
                if key == numidx then
                    subpath = subpath .. "[" .. numidx .. "]"
                    numidx = numidx + 1
                else
                    s = keycache[key]
                    if not s:match "^%[" then
                        subpath = subpath .. "."
                    end
                    subpath = subpath .. s:gsub("%s*=%s*$", "")
                end
                s = s .. dumplua(val, ident + 1, subpath)
                str[#str + 1] = s
                totallen = totallen + #s + 2
            end
            if totallen > 80 then
                sep = "\n" .. string_rep("  ", ident + 1)
            end
            local _str = "{" .. sep .. table_concat(str, "," .. sep) .. " " .. sep:sub(1, -3) .. "}"
            if meta then
                sep = sep:sub(1, -3)
                return "setmetatable(" .. sep .. _str .. "," .. sep .. metastr .. sep:sub(1, -3) .. ")"
            end
            return _str
        end
        fcts['function'] = function(value, ident, path)
            if test_defined(value, path) then
                return "nil"
            end
            if c_functions[value] then
                return c_functions[value]
            elseif debug == nil or debug.getupvalue(value, 1) == nil then
                return string_format("loadstring(%q)", string_dump(value))
            end
            closure_cnt = closure_cnt + 1
            local res = { string.dump(value) }
            for i = 1, math.huge do
                local name, v = debug.getupvalue(value, i)
                if name == nil then
                    break
                end
                res[i + 1] = v
            end
            return "closure " .. dumplua(res, ident, "closures[" .. closure_cnt .. "]")
        end
    end
    function dumplua(value, ident, path)
        return fcts[type(value)](value, ident, path)
    end
    if varname == nil then
        varname = "return "
    elseif varname:match("^[%a_][%w_]*$") then
        varname = varname .. " = "
    end
    if fastmode then
        setmetatable(keycache, { __index = make_key })
        out[1] = varname
        table.insert(out, dumplua(value, 0))
        return table.concat(out)
    else
        setmetatable(keycache, { __index = make_key })
        local items = {}
        for i = 1, 10 do
            items[i] = ''
        end
        items[3] = dumplua(value, ident or 0, "t")
        if closure_cnt > 0 then
            items[1], items[6] = dumplua_closure:match("(.*\n)\n(.*)")
            out[#out + 1] = ""
        end
        if #out > 0 then
            items[2], items[4] = "local t = ", "\n"
            items[5] = table.concat(out)
            items[7] = varname .. "t"
        else
            items[2] = varname
        end
        return table.concat(items)
    end
end
--摘至《饥荒》游戏。

--tab合并
function tabMerge(tab1, tab2)
    local tab = table.clone(tab1)
    table_foreach(tab2, function(k, v)
        insert(tab, v)
    end)
    return tab
end

function table.unique(t, bArray)
    local check = {}
    local n = {}
    local idx = 1
    for k, v in pairs(t) do
        if not check[v] then
            if bArray then
                n[idx] = v
                idx = idx + 1
            else
                n[k] = v
            end
            check[v] = true
        end
    end
    return n
end
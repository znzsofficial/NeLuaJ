local function test(func, ...)
    local old_hook = debug.gethook()
    local start_time = os.clock()
    local elapsed = 0.0
    local arg = { ... }
    local result = { xpcall(function()
        return func(unpack(arg))
    end, debug.traceback) }
    debug.sethook(function(event)
        if event == "return" then
            elapsed = os.clock() - start_time
            debug.sethook(old_hook)
        end
    end, "r")
    if debug.gethook() ~= nil then
        debug.sethook(old_hook)
    end
    return elapsed, unpack(result)
end

return test
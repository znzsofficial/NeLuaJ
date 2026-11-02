-- Real context, PathManager, Workspace and EditorSession modules; Android/KV
-- boundaries only are doubled. Every suite runs in an isolated LuaJ++ JVM.
local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
Bean = nil
local Context = require "mods.project.ProjectContext"
local PathManager = require "mods.utils.PathManager"
assert(Context.snapshot().directory == "", "module loading must not require Bean")
assert(not pcall(PathManager.updateFile, "/not-initialized.lua"))
assert(not pcall(PathManager.updateDir, "/not-initialized"))

local normalize = Context.normalize
assert(normalize(nil) == "" and normalize("") == "")
assert(normalize("/") == "/" and normalize("////") == "/")
assert(normalize("/Projects//Alpha/./src/../") == "/Projects/Alpha")
assert(normalize("/../../Alpha") == "/Alpha")
assert(normalize("../Alpha/../Beta") == "../Beta")
assert(normalize("Alpha/..") == ".")
assert(normalize("/Projects/中文 工程/") == "/Projects/中文 工程")
assert(Context.contains("/Projects/Alpha/main.lua", "/Projects/Alpha/"))
assert(not Context.contains("/Projects/Alpha2/main.lua", "/Projects/Alpha"))
assert(Context.contains("/main.lua", "/"))
print("PASS lexical normalization preserves root and segment boundaries")

Bean = {
    Path = { app_root_pro_dir = "/Projects/", this_dir = "/Projects/Alpha/src",
        this_file = "/Projects/Beta/open.lua", agent_root_dir = "/agents" },
    Project = { this_project = "Beta" }, -- editor title is not browser identity
}
local initial = Context.snapshot()
assert(initial.projectRoot == "/Projects/Alpha" and initial.projectName == "Alpha")
assert(initial.directory == "/Projects/Alpha/src")
assert(initial.editorProjectRoot == "/Projects/Beta")
assert(initial.scopePath == "/Projects/Alpha" and initial.agentRoot == "/agents")
assert(Context.projectKeyOf("/ProjectsBackup/Alpha") == nil)
assert(Context.projectKeyOf("/Projects") == nil)
assert(Context.projectKeyOf("/Projects/Alpha/../../outside") == nil)
assert(Context.projectKeyOf("/Alpha/src", "/") == "/Alpha")
initial.directory = "mutated snapshot"
assert(Context.snapshot().directory == "/Projects/Alpha/src", "snapshots must be detached")
initial = Context.snapshot()
Bean.Path.this_dir = "/Projects/Alpha/other/"
local nested = Context.snapshot()
assert(nested.generation > initial.generation)
assert(nested.projectGeneration == initial.projectGeneration)
assert(Context.isCurrent(initial, "project") and not Context.isCurrent(initial, "editor"))
Context.setFile("/Projects/Alpha/new.lua")
assert(Bean.Path.this_file == "/Projects/Alpha/new.lua")
assert(Context.isCurrent(nested) and not Context.isCurrent(nested, "editor"))
local away = Context.setDirectory("/Projects/Beta")
assert(not Context.isCurrent(initial))
Context.setDirectory("/Projects/Alpha/src")
assert(not Context.isCurrent(initial), "switching back must not resurrect old ownership")
assert(not Context.isCurrent(away))
local beforeLegacySwitch = Context.snapshot()
Bean.Path.this_dir = "/Projects/Beta"
Context.setDirectory("/Projects/Alpha/src")
assert(not Context.isCurrent(beforeLegacySwitch), "setters must observe intervening legacy writes")
local beforeNoop = Context.snapshot()
Context.setDirectory("/Projects/Alpha/./src/")
assert(Context.isCurrent(beforeNoop, "editor"), "normalized no-op must retain ownership")
local isolated = Context.new(function() return Bean end)
assert(not isolated.isCurrent(Context.snapshot()), "ownership must be instance-specific")
local beforeReplace = Context.snapshot()
local oldPaths = Bean.Path
Bean.Path = {
    app_root_pro_dir = oldPaths.app_root_pro_dir, this_dir = oldPaths.this_dir,
    this_file = oldPaths.this_file, agent_root_dir = oldPaths.agent_root_dir,
}
assert(not Context.isCurrent(beforeReplace), "replacing Bean.Path invalidates its owner generation")
local beforeAgentRoot = Context.snapshot()
Bean.Path.agent_root_dir = "/other-agents"
assert(not Context.isCurrent(beforeAgentRoot))
assert(Context.setDirectory("/outside/nested").projectRoot == nil)
assert(Context.snapshot().scopePath == "/outside/nested")
assert(Context.setDirectory("/").directory == "/")
assert(not pcall(Context.setDirectory, "relative"))
print("PASS lazy Bean compatibility, detached snapshots, distinct project/editor ownership")

local events, warnings = {}, {}
local failStage
local function event(stage)
    events[#events + 1] = stage .. ":" .. tostring(Bean.Path.this_dir)
    if failStage == stage then error("simulated " .. stage .. " failure") end
end
local workspaceDouble = { saveFor = function(path)
    assert(path == Context.normalize(Bean.Path.this_dir), "save must see the old directory")
    event("save")
    if failStage == "write" then return false, "workspace write failed" end
    return true
end }
package.loaded["activities.main.Workspace"] = workspaceDouble
package.loaded["mods.agent.ChatUI"] = {
    onBeforeProjectChange = function() event("cancel") end,
    refreshProjectContext = function() event("refresh") end,
}
package.loaded["mods.agent.AgentChat"] = {
    syncAgentProjectScope = function() event("rebind") end,
}
local realPrint = print
print = function(message) warnings[#warnings + 1] = message end
Bean.Path.this_dir = "/Projects/Alpha"
local current, diagnostics = PathManager.updateDir("/Projects/Beta/./src/../")
assert(current.projectRoot == "/Projects/Beta" and #diagnostics == 0)
assert(Bean.Path.this_dir == "/Projects/Beta")
assert(table.concat(events, ",") == "save:/Projects/Alpha,cancel:/Projects/Alpha,rebind:/Projects/Beta,refresh:/Projects/Beta")
for stage, diagnosticStage in pairs({ save = "workspace.save", cancel = "agent.beforeChange",
    rebind = "agent.rebind", refresh = "agent.refresh", write = "workspace.save" }) do
    events = {}
    Bean.Path.this_dir = "/Projects/Alpha"
    failStage = stage
    current, diagnostics = PathManager.updateDir("/Projects/Beta")
    assert(Bean.Path.this_dir == "/Projects/Beta" and #events == 4)
    assert(#diagnostics == 1 and diagnostics[1].stage == diagnosticStage)
    assert(diagnostics[1].message:find("failure", 1, true) or diagnostics[1].message:find("failed", 1, true))
end
failStage = nil
events = {}
local beforeInvalid = Context.snapshot()
assert(not pcall(PathManager.updateDir, "relative"))
assert(#events == 0 and Context.isCurrent(beforeInvalid, "editor"))
workspaceDouble.saveFor = function() return false end -- non-editor skip is normal
current, diagnostics = PathManager.updateDir("/Projects/Alpha")
assert(#diagnostics == 0)
package.loaded["mods.agent.AgentChat"].syncAgentProjectScope = function() return false end
current, diagnostics = PathManager.updateDir("/Projects/Alpha")
assert(#diagnostics == 1 and diagnostics[1].stage == "agent.rebind")
assert(#warnings == 6)
print = realPrint
print("PASS actual PathManager preserves hook order, best-effort failures and diagnostics")

local files = {
    ["/Projects/Alpha/main.lua"] = true, ["/Projects/Alpha/src/other.lua"] = true,
    ["/Projects/Beta/open.lua"] = true, ["/Projects/Alpha2/no.lua"] = true,
}
luajava = { bindClass = function(name)
    assert(name == "java.io.File")
    return function(path)
        return { isFile = function(...)
            assert(select("#", ...) == 0, "Java members must be called with dot")
            return files[path] == true
        end }
    end
end }
local Session = assert(loadfile(assets .. "mods/editor/EditorSession.lua"))()
package.loaded["mods.editor.EditorSession"] = Session
local tabTable, added, loaded, stored = {}, {}, {}, {}
local saveResult, selected = true, nil
package.loaded["mods.utils.LuaKV"] = {
    set = function(ns, key, value)
        assert(ns == "workspace")
        stored[key] = value
        return saveResult
    end,
    get = function(ns, key) assert(ns == "workspace"); return stored[key] end,
}
package.loaded["mods.utils.TabUtil"] = {
    Table = tabTable,
    add = function(path, options)
        assert(options.select == false)
        added[#added + 1] = path
    end,
}
package.loaded["mods.utils.EditorUtil"] = {
    currentFile = function() return Session.current() end,
    load = function(path) loaded[#loaded + 1] = path; return true end,
    setSelection = function(position) selected = position end,
}
local Workspace = assert(loadfile(assets .. "activities/main/Workspace.lua"))()
Bean.Path.this_dir = "/Projects/Alpha/src"
mLuaEditor = nil
assert(Workspace.saveFor() == false and Workspace.restoreCurrent() == false)
mLuaEditor = { getSelectionEnd = function(...)
    assert(select("#", ...) == 0, "Java editor members must be called with dot")
    return 17
end }
for path in pairs(files) do tabTable[path] = {}; Session.remember(path); Session.setCursor(path, 4) end
tabTable["/Projects/Alpha/missing.lua"] = {}
Session.setCurrent("/Projects/Alpha/main.lua")
assert(Workspace.saveFor())
local saved = assert(stored["/Projects/Alpha"])
assert(#saved.tabs == 2 and saved.active == "/Projects/Alpha/main.lua" and saved.select == 17)
assert(saved.cursors["/Projects/Beta/open.lua"] == nil)
assert(saved.cursors["/Projects/Alpha2/no.lua"] == nil)
saveResult = false
local ok, detail = Workspace.saveFor()
assert(ok == false and detail:find("/Projects/Alpha", 1, true))
saveResult = true
assert(Workspace.saveFor("/ProjectsBackup/Alpha") == false)
assert(Workspace.saveFor("/Projects") == false)
assert(Workspace.restoreCurrent())
assert(#added == 1 and added[1] == "/Projects/Alpha/src/other.lua")
assert(#loaded == 1 and loaded[1] == "/Projects/Alpha/main.lua" and selected == 17)

-- A corrupt/old record must not import another project's tabs or cursor state.
stored["/Projects/Alpha"] = {
    tabs = { "/Projects/Beta/open.lua", "/Projects/Alpha2/no.lua", "/Projects/Alpha/src/../../Beta/open.lua" },
    active = "/Projects/Beta/open.lua", cursors = { ["/Projects/Beta/open.lua"] = 999 },
}
local oldBetaCursor = Session.cursor("/Projects/Beta/open.lua")
assert(not Workspace.restoreCurrent())
assert(#added == 1 and #loaded == 1 and Session.cursor("/Projects/Beta/open.lua") == oldBetaCursor)
print("PASS actual Workspace saves by project root and rejects foreign restored state")
print("ALL-PASS")

local assets = ASSETS or "app/src/main/assets/"
package.path = assets .. "?.lua;" .. package.path
local Generator = require "mods.project.templates.Generator"

local generator = Generator.new({ fs = {
  checkRoot = function() return true end,
  exists = function() return false end,
} })

-- Explicit runtime fixtures are independent of the original generator choice.
-- Values match Android TypedValue booleans, including its numeric false (0).
local BOOLEAN = 18
local function boolean(value) return { type = BOOLEAN, data = value and 1 or 0 } end
local runtimeThemes = {
  { name = "M3 NoActionBar", material = true, attrs = { bar = boolean(false), m3 = boolean(true), mc = boolean(true) } },
  { name = "M3 system ActionBar", material = true, system = true, attrs = { bar = boolean(true), m3 = boolean(true), mc = boolean(true) } },
  { name = "Compat NoActionBar", attrs = { bar = boolean(false) } },
  { name = "Compat system ActionBar", system = true, attrs = { bar = boolean(true) } },
  { name = "MC NoActionBar", material = true, attrs = { bar = boolean(false), mc = boolean(true) } },
  { name = "MC system ActionBar", material = true, system = true, attrs = { bar = boolean(true), mc = boolean(true) } },
  { name = "Dynamic NoActionBar", material = true, attrs = { bar = boolean(false), m3 = boolean(true) } },
  { name = "Dynamic system ActionBar", material = true, system = true, attrs = { bar = boolean(true), m3 = boolean(true) } },
  { name = "Explicit false Material markers", attrs = { bar = boolean(false), mc = boolean(false), m3 = boolean(false) } },
  { name = "Nonboolean markers are not true", attrs = { bar = { type = 16, data = 1 }, mc = { type = 16, data = 1 } } },
}

local checks = 0
for _, generatedTheme in ipairs({ "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay", "Theme_NeLuaJ_Compat" }) do
  local preview = generator.preview({ templateId = "blank", appName = "Runtime theme",
    packageName = "com.example.runtime", rootPath = "/Projects", themeName = generatedTheme })
  assert(preview.ok, preview.error)
  local source
  for _, file in ipairs(preview.files) do
    if file.path == "app/screen.lua" then source = file.content end
  end
  assert(source, "test must execute the actual generated helper")

  local current, installed, events, barTitle
  local bindings = {}
  local classes = {
    ["android.widget.LinearLayout"] = "LinearLayout",
    ["androidx.appcompat.widget.Toolbar"] = "CompatToolbar",
    ["com.google.android.material.appbar.MaterialToolbar"] = "MaterialToolbar",
    ["androidx.appcompat.R$attr"] = { windowActionBar = "bar" },
    ["com.google.android.material.R$attr"] = { isMaterialTheme = "mc", isMaterial3Theme = "m3" },
    ["android.util.TypedValue"] = setmetatable({ TYPE_INT_BOOLEAN = BOOLEAN }, {
      __call = function() return {} end,
    }),
  }
  local activity = {
    getTheme = function()
      local attributes = current.attrs
      return { resolveAttribute = function(attribute, value, resolveRefs)
        assert(resolveRefs == true, "resource references must resolve to typed values")
        local entry = attributes[attribute]
        if not entry then return false end
        value.type, value.data = entry.type, entry.data
        return true
      end }
    end,
    setContentView = function() events[#events + 1] = "content" end,
    setSupportActionBar = function(toolbar)
      assert(not current.system, "cannot install Toolbar over a system ActionBar")
      assert(events[1] == "content", "content must be installed first")
      installed = toolbar
      events[#events + 1] = "toolbar"
    end,
    getSupportActionBar = function()
      if current.system or installed then
        return { setTitle = function(title) barTitle = title end }
      end
      return nil
    end,
    setTitle = function(title) assert(title == "Updated title") end,
  }
  local function forbidden() error("configuration must not be read or executed again") end
  local env = setmetatable({
    activity = activity, io = { open = forbidden }, loadfile = forbidden, dofile = forbidden,
    luajava = { bindClass = function(name)
      assert(classes[name], "unexpected class " .. name)
      bindings[name] = (bindings[name] or 0) + 1
      return classes[name]
    end },
    loadlayout = function(layout, views)
      for _, child in ipairs(layout) do
        if type(child) == "table" and child.id == "toolbar" then views.toolbar = child[1] end
      end
      return layout
    end,
  }, { __index = _G })

  -- Re-execute the same generated module with a different initial theme, then
  -- mutate the active theme while retaining the helper to catch cached flags too.
  for _, initial in ipairs({ runtimeThemes[1], runtimeThemes[4] }) do
    current, bindings = initial, {}
    local screen = assert(load(source, "generated/app/screen.lua", "t", env))()
    for _, fixture in ipairs(runtimeThemes) do
      current = fixture
      for _, showToolbar in ipairs({ true, false }) do
        local body = { "Body" }
        local layout = screen.wrap(body, showToolbar)
        local expectedToolbar = not fixture.system and showToolbar
        assert(layout[#layout] == body)
        assert(#layout == (expectedToolbar and 3 or 2), fixture.name .. ": wrong toolbar count")
        assert((layout.BackgroundColor ~= nil) == (fixture.material == true), fixture.name .. ": wrong surface attribute")
        if expectedToolbar then
          local expected = fixture.material and "MaterialToolbar" or "CompatToolbar"
          assert(layout[2][1] == expected, fixture.name .. ": wrong toolbar class")
        end
        installed, events, barTitle = nil, {}, nil
        screen.show(layout, "Updated title")
        assert(events[1] == "content")
        assert((installed ~= nil) == expectedToolbar)
        assert((barTitle ~= nil) == (fixture.system == true or expectedToolbar))
        for name, count in pairs(bindings) do assert(count == 1, "rebound class " .. name) end
        checks = checks + 1
      end
    end
  end
end

print("ALL-PASS TestTemplateScreen (" .. checks .. " generated runtime theme/toolbar transitions)")

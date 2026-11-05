local bindClass = luajava.bindClass
local WebViewClient = bindClass "android.webkit.WebViewClient"
local Screen = require "app.screen"
local views = Screen.show(require "res.layout.main", res.string.app_title)
local web = views.web
local settings = web.getSettings()
settings.setJavaScriptEnabled(true)
settings.setDomStorageEnabled(false)
settings.setAllowFileAccess(false)
settings.setAllowContentAccess(false)
settings.setAllowFileAccessFromFileURLs(false)
settings.setAllowUniversalAccessFromFileURLs(false)
settings.setBlockNetworkLoads(true)
web.setWebViewClient(WebViewClient())

local function readLocal(name)
  local path = activity.getLuaPath("web/" .. name)
  local file, reason = io.open(path, "rb")
  assert(file, reason)
  local contents = file:read("*a")
  file:close()
  assert(contents, "Could not read " .. name)
  return contents
end

-- Inline bundled resources so WebView needs neither filesystem nor network access.
local ok = pcall(function()
  local html = readLocal("index.html")
  local css = readLocal("style.css")
  local js = readLocal("app.js")
  html = html:gsub('<link rel="stylesheet" href="style%.css">', function()
    return "<style>" .. css .. "</style>"
  end)
  html = html:gsub('<script src="app%.js"></script>', function()
    return "<script>" .. js .. "</script>"
  end)
  web.loadDataWithBaseURL("https://local.invalid/", html, "text/html", "UTF-8", nil)
end)
if not ok then views.status.setText(res.string.web_failed) end

activity.addOnBackPressedCallback(function()
  if not web then return end
  if web.canGoBack() then
    web.goBack()
  else
    activity.finish()
  end
end)

function onPause()
  if web then web.onPause() end
end

function onResume()
  if web then web.onResume() end
end

function onDestroy()
  if not web then return end
  web.stopLoading()
  local parent = web.getParent()
  if parent then parent.removeView(web) end
  web.destroy()
  web = nil
  views.web = nil
end

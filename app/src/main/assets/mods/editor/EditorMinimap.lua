--- 代码缩略图。不负责打开或保存文件。
local Color = bindClass "android.graphics.Color"
local View = bindClass "android.view.View"
local MotionEvent = bindClass "android.view.MotionEvent"
local LuaCodeMinimapView = bindClass "com.androlua.LuaCodeMinimapView"

local _M = {}
local GONE = View.GONE
local VISIBLE = View.VISIBLE

local function enabled()
    local value = this.getSharedData("code_minimap", true)
    return value == true or value == "true" or value == 1
end

local function color(data, key, fallback)
    local raw = data and data[key]
    if not raw then return fallback end
    local ok, parsed = pcall(Color.parseColor, raw)
    if ok then return parsed end
    return fallback
end

local function config(editor)
    local data = this.sharedData
    local cfg = LuaCodeMinimapView.MinimapConfig()
    cfg.lineHeight = 2.2
    cfg.charWidthAscii = 1.05
    cfg.verticalGap = 0.55
    cfg.paddingLeft = 3
    cfg.backgroundColor = color(data, "MinimapBg", Color.argb(0, 0, 0, 0))
    cfg.outsideDimColor = Color.argb(0, 0, 0, 0)
    cfg.maskColor = color(data, "MinimapMask", Color.argb(0x28, 0x21, 0x96, 0xF3))
    cfg.codeAlpha = 200
    local raw = this.getSharedData("code_minimap_alpha", nil)
    local alpha = tonumber(raw)
    if alpha then
        alpha = math.floor(alpha + 0.5)
        if alpha < 0 then alpha = 0 end
        if alpha > 255 then alpha = 255 end
        cfg.codeAlpha = alpha
    end
    cfg.colorDefault = color(data, "BaseWord", Color.argb(255, 0x44, 0x77, 0xe0))
    cfg.colorKeyword = color(data, "KeyWord", Color.argb(255, 0xb4, 0x00, 0x2d))
    cfg.colorString = color(data, "String", Color.argb(255, 0xc2, 0x18, 0x5b))
    cfg.colorComment = color(data, "Comment", Color.argb(255, 0x71, 0x78, 0x7E))
    cfg.colorNumber = color(data, "UserWord", Color.argb(255, 0x5c, 0x6b, 0xc0))
    cfg.colorId = color(data, "Global", Color.argb(255, 0x68, 0x9f, 0x38))
    cfg.tileHeightPx = 1024
    cfg.maxTileCount = 8
    if editor then
        pcall(function()
            local size = editor.getTextSize()
            if size and size > 0 then
                cfg.charWidthAscii = math.max(0.7, size / 30)
            end
        end)
    end
    return cfg
end

local function scale()
    local n = tonumber(this.getSharedData("code_minimap_scale", 1.0))
    if not n or n ~= n then return 1.0 end
    if n < 0.55 then return 0.55 end
    if n > 2.8 then return 2.8 end
    return n
end

function _M.refresh(full)
    if not mCodeMinimap then return end
    if not enabled() then
        mCodeMinimap.setVisibility(GONE)
        if minimap_divider then minimap_divider.setVisibility(GONE) end
        pcall(function() mCodeMinimap.detachEditor() end)
        return
    end
    mCodeMinimap.setVisibility(VISIBLE)
    if minimap_divider then minimap_divider.setVisibility(GONE) end
    pcall(function()
        mCodeMinimap.setBackgroundColor(0)
        mCodeMinimap.setClickable(true)
        mCodeMinimap.bringToFront()
    end)
    mCodeMinimap.configure(config(mLuaEditor))
    mCodeMinimap.setScale(scale())
    mCodeMinimap.setScaleListener(LuaCodeMinimapView.ScaleListener {
        onScaleChanged = function(value)
            this.setSharedData("code_minimap_scale", value)
        end
    })
    mCodeMinimap.attachToEditor(mLuaEditor)
    mCodeMinimap.scheduleCodeRefresh(full and 0 or 120)
    mCodeMinimap.syncVisibleRangeFromEditor(false)
end

function _M.noteEdit(delay)
    if not mCodeMinimap or not enabled() then return end
    mCodeMinimap.scheduleCodeRefresh(delay or 60)
    mCodeMinimap.syncVisibleRangeFromEditor(false)
end

function _M.syncSelection()
    if mCodeMinimap and enabled() then
        mCodeMinimap.syncVisibleRangeFromEditor(true)
    end
end

function _M.onTouch(event)
    if not mCodeMinimap or not enabled() then return end
    local action = event.action
    if action == MotionEvent.ACTION_UP then
        mCodeMinimap.scheduleCodeRefresh(350)
    end
    if action == MotionEvent.ACTION_MOVE or action == MotionEvent.ACTION_UP then
        mCodeMinimap.syncVisibleRangeFromEditor(true)
    end
end

return _M

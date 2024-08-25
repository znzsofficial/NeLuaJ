local _M = {}
local res = res
local Bean = Bean
import "androidx.core.view.GravityCompat"
import "androidx.appcompat.app.ActionBarDrawerToggle"
--Material
import "com.google.android.material.snackbar.Snackbar"

import "mods.functions.SearchCode"
import "mods.utils.EditorUtil"

_M.initView = function()
    local toggle = ActionBarDrawerToggle(activity, drawer, R.string.drawer_open, R.string.drawer_close)
    drawer.setDrawerListener(toggle);
    toggle.syncState();
    filetab.setPath(Bean.Path.this_dir)
    mSearch.setVisibility(8)
    mSearch.post(function()
        SearchCode()
    end)
    mLuaEditor.setVisibility(4)
    mLuaEditor.post(function()
        EditorUtil.init()
    end)
    swipeRefresh.onRefresh = function()
        MainActivity.RecyclerView.update()
    end
    return _M
end

_M.initBar = function()
    local loadlayout = loadlayout
    local LinearLayout = luajava.bindClass "android.widget.LinearLayout"
    local TextView = luajava.bindClass "android.widget.TextView"
    local rippleRes = activity.obtainStyledAttributes({ android.R.attr.selectableItemBackground }).getResourceId(0, 0)
    local t = {
        "fun", "(", ")", "[", "]", "{", "}",
        "\"", "=", ":", ".", ",", ";", "_",
        "+", "-", "*", "/", "\\", "%",
        "#", "^", "$", "?", "&", "|",
        "<", ">", "~", "'"
    }
    for k, v in ipairs(t) do
        local Item = loadlayout({
            LinearLayout,
            layout_width = "40dp",
            layout_height = "36dp",
            {
                TextView,
                layout_width = "40dp",
                layout_height = "36dp",
                gravity = "center",
                clickable = true,
                focusable = true,
                TextSize = "5sp",
                BackgroundResource = rippleRes,
                text = v,
                onClick = function()
                    if v == "fun" then
                        v = "function()"
                    end
                    mLuaEditor.paste(v)
                end,
            },
        })
        ps_bar.addView(Item)
    end
    return _M
end

return _M
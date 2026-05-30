require "environment"
import "android.widget.LinearLayout"
import "android.widget.ListView"
import "androidx.viewpager2.widget.ViewPager2"
local LuaFragmentAdapter = luajava.bindClass "github.znzsofficial.adapter.LuaFragmentAdapter"
local LuaFragment = luajava.bindClass "com.androlua.LuaFragment"
local ColorUtil = this.themeUtil

local view = loadlayout {
    LinearLayout,
    layout_width = "-1",
    layout_height = "-1",
    orientation = "vertical",
    {
        ViewPager2,
        layout_width = "-1",
        layout_height = "-1",
        id = "vpg",
        UserInputEnabled = false,
        OffscreenPageLimit = 1,
    },
}

local pages = {
    -----
    loadlayout {
        ListView,
        id = "lv",
        layout_width = "-1",
        layout_height = "-1",
        DividerHeight = 0,
        backgroundColor = ColorUtil.getColorSurfaceVariant(),
    },
    -----
    loadlayout {
        import "com.androlua.LuaWebView",
        id = "webView",
        layout_width = "match",
        layout_height = "match",
        backgroundColor = ColorUtil.getColorBackground(),
    },
    -----
}

local list = { LuaFragment(LuaFragment.Creator {
    onCreateView = function()
        return pages[1]
    end
}), LuaFragment(LuaFragment.Creator {
    onCreateView = function()
        return pages[2]
    end
}) }
local adapter = LuaFragmentAdapter(activity, LuaFragmentAdapter.Creator {
    createFragment = function(i)
        return list[i + 1]
    end,
    getItemCount = function()
        return #list
    end,
})

vpg.setAdapter(adapter)

return view
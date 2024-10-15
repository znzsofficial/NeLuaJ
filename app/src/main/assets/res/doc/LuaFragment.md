LuaFragment 继承自 AndroidX Fragment

## Creator支持的方法

```
     onAttach(context: Context)
     onCreate(savedInstanceState: Bundle?)
     onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View?

     onViewCreated(view: View, savedInstanceState: Bundle?)
     onActivityCreated(savedInstanceState: Bundle?)
     onStart()
     onResume()
     onPause()
     onStop()
     onDestroyView()
     onDestroy()
     onDetach()
     onSaveInstanceState(outState: Bundle)
     onViewStateRestored(savedInstanceState: Bundle?)
     onContextItemSelected(item: MenuItem): Boolean
     onCreateContextMenu(menu: ContextMenu, v: View, menuInfo: ContextMenu.ContextMenuInfo?)
```

```lua
local LuaFragment = luajava.bindClass "com.androlua.LuaFragment"

local fragment = LuaFragment(LuaFragment.Creator {
    --onCreateView = lambda(): res.view.fragment_main
    onCreateView = function(layoutInflater, viewGroup, bundle)
        -- 保存控件的表
        local binding = {}
        -- 加载布局，并把binding放到布局的tag里
        return loadlayout(res.layout.fragment_main, binding) { tag = binding }
    end,
    onViewCreated = function(view, bundle)
        -- 取出binding
        local binding = view.tag
        binding.mainButton.onClick = function()
            print("Fragment")
        end
    end
})

this.setFragment(fragment)

--偷懒写法
fragment = LuaFragment(LuaFragment.Creator {
    onCreateView = function(layoutInflater, viewGroup, bundle)

        -- 加载布局
        local view = loadlayout(res.layout.fragment_main)
        -- 从全局环境中获取控件
        mainButton.onClick = function()
            print("Fragment")
        end

        -- onCreateView 的返回值是要显示的布局
        return view
    end
})
```
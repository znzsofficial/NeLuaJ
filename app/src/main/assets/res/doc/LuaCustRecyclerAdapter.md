### 介绍
RecyclerView通过对资源的缓存复用来增强性能。LuaCustRecyclerAdapter可以帮助你以贴近原生开发的风格创建适配器。

PopupRecyclerAdapter 作为 LuaCustRecyclerAdapter 的子类，可以通过实现getPopupText方法为FastScrollerBuilder提供支持
### 示例

```lua
LuaCustRecyclerAdapter(
        -- 上下文可选，便于抛出异常
        activity,
        -- 实现适配器的接口，接口类型可省略
        LuaCustRecyclerAdapter.Creator({
            getItemCount = function()
                return #List
            end,
            getItemViewType = function()
                return 0
            end,
            onCreateViewHolder = function(parent, viewType)
                local views = {}
                local holder = LuaCustRecyclerHolder(loadlayout(item_layout, views))
                holder.views = views
                return holder
            end,
            onBindViewHolder = function(holder, position)
                local view = holder.views
                local v = List[position + 1]
            end,
        }))

PopupRecyclerAdapter(
        -- 上下文可选，便于抛出异常
        activity,
        -- 实现适配器的接口，接口类型可省略
        PopupRecyclerAdapter.PopupCreator({
            getItemCount = function()
                return #List
            end,
            getItemViewType = function()
                return 0
            end,
            getPopupText = function(view, position)
                return utf8.sub(List[position + 1].name, 1, 1)
            end,
            onCreateViewHolder = function(parent, viewType)
                local views = {}
                local holder = LuaCustRecyclerHolder(loadlayout(item_layout, views))
                holder.views = views
                return holder
            end,
            onBindViewHolder = function(holder, position)
                local view = holder.views
                local v = List[position + 1]
            end,
        }))

```
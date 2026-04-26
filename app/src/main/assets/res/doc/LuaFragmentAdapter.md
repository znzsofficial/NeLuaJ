# LuaFragmentAdapter

## 介绍

与 ViewPager 不同，ViewPager2 利用了 RecyclerView 的优化能力使得它更具有灵活性和可扩展性。例如，ViewPager2 支持垂直滑动、RTL(从右到左) 布局、无限循环滑动等功能。此外，ViewPager2 还提供了监听页面改变和滑动事件的回调接口，让开发者可以在合适的时机处理一些操作，比如：页面渲染完毕时请求数据等。另外，由于采用 RecyclerView 作为底层实现，ViewPager2 的性能也得到了进一步提升。

LuaFragmentAdapter 继承 FragmentStateAdapter，可以帮助你以贴近原生开发的风格创建适配器。

## 示例

```lua
LuaFragmentAdapter(activity,
        LuaFragmentAdapter.Creator {
            createFragment = function(i)
                return Fragments[i + 1]
            end,
            getItemCount = function()
                return #Fragments
            end,
        })
```

## 刷新页面

LuaFragmentAdapter 提供了几个便于 Lua 调用的刷新方法：

| 方法 | 描述 |
| :--- | :--- |
| `reload()` | 刷新全部页面 |
| `reloadItem(position)` | 刷新指定位置页面 |
| `changed(position, count)` | 通知一段页面内容变化 |
| `inserted(position, count)` | 通知插入一段页面 |
| `removed(position, count)` | 通知移除一段页面 |
| `moved(fromPosition, toPosition)` | 通知页面移动 |

示例：

```lua
table.insert(Fragments, newFragment)
adapter.inserted(#Fragments - 1, 1)

table.remove(Fragments, index)
adapter.removed(index - 1, 1)

adapter.reload()
```

注意：`position` 使用 ViewPager2/RecyclerView 的索引，从 `0` 开始。

## 稳定 ID

如果页面会动态增删或重排，建议使用 `StableIdCreator` 提供稳定 ID，避免 Fragment 状态错乱。

```lua
local ids = { 1001, 1002, 1003 }

local adapter = LuaFragmentAdapter(activity,
    LuaFragmentAdapter.StableIdCreator {
        createFragment = function(i)
            return Fragments[i + 1]
        end,
        getItemCount = function()
            return #Fragments
        end,
        getItemId = function(i)
            return ids[i + 1]
        end,
        containsItem = function(id)
            for _, v in ipairs(ids) do
                if v == id then
                    return true
                end
            end
            return false
        end,
    })
```

## 视图类型

如需给不同页面返回不同的 RecyclerView item type，可使用 `ViewTypeCreator`。

```lua
local adapter = LuaFragmentAdapter(activity,
    LuaFragmentAdapter.ViewTypeCreator {
        createFragment = function(i)
            return Fragments[i + 1]
        end,
        getItemCount = function()
            return #Fragments
        end,
        getItemViewType = function(i)
            return i % 2
        end,
    })
```

## 错误处理

当 `createFragment` 或 `getItemCount` 抛出异常时，LuaFragmentAdapter 会通过 `activity.sendError("FragmentAdapter", e)` 输出错误，并使用安全默认值避免 ViewPager2 崩溃。

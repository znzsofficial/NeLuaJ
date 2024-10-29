### 介绍
与 ViewPager 不同，ViewPager2 利用了 RecyclerView 的优化能力使得它更具有灵活性和可扩展性。例如，ViewPager2 支持垂直滑动、RTL(从右到左) 布局、无限循环滑动等功能。此外，ViewPager2 还提供了监听页面改变和滑动事件的回调接口，让开发者可以在合适的时机处理一些操作，比如：页面渲染完毕时请求数据等。另外，由于采用 RecyclerView 作为底层实现，ViewPager2 的性能也得到了进一步提升。

LuaFragmentAdapter 继承 FragmentStateAdapter，可以帮助你以贴近原生开发的风格创建适配器。

### 示例

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
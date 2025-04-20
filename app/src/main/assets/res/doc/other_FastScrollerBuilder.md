## FastScrollerBuilder 示例
[AndroidFastScroll](https://github.com/zhanghai/AndroidFastScroll)
搭配 PopupRecyclerAdapter 或 PopupRecyclerListAdapter 的 getPopupText 方法使用实现弹出窗口

```lua
local FastScrollerBuilder = luajava.bindClass "me.zhanghai.android.fastscroll.FastScrollerBuilder"
-- 创建一个 FastScrollerBuilder 对象，并设置 RecyclerView 对象
local builder = FastScrollerBuilder(recyclerView)
           .useMd2Style() -- 设置圆角样式
           .setPadding(0,
            this.dpToPx(8),
            this.dpToPx(2),
            this.dpToPx(8))  -- 设置内边距
           .build()
```
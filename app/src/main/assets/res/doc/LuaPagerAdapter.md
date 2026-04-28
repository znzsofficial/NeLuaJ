# `LuaPagerAdapter` API

`LuaPagerAdapter` 是用于 `androidx.viewpager.widget.ViewPager` 的自定义 `PagerAdapter`，用于在 LuaJ+ 中动态管理页面 `View` 和可选标题。

也可以通过在布局表中给 `ViewPager` 设置 `pages` 或 `pagesWithTitle` 来自动创建并填充 `LuaPagerAdapter`。

## 导入类

```lua
local LuaPagerAdapter = luajava.bindClass("github.daisukiKaffuChino.LuaPagerAdapter")
```

## 设计说明

`LuaPagerAdapter` 使用无参构造，并在 Java 侧内部维护页面列表和标题列表。这样可以避免 LuaJ 包装 Lua table 后，Java 侧无法感知 table 后续变更而导致 `ViewPager` 不刷新的问题。

适配器在 `setData`、`add`、`insert`、`set`、`remove`、`clear` 后会自动调用 `notifyDataSetChanged()`。同时已重写 `getItemPosition()`，便于页面动态更新。

**索引说明：** 所有 `index` / `position` 均为 Java/Android 风格的 **0 基索引**。Lua 表通常从 1 开始，从 Lua 调用这些方法时请注意转换。

## 构造函数

### `LuaPagerAdapter()`

创建一个空的页面适配器。

```lua
local adapter = LuaPagerAdapter()
pager.setAdapter(adapter)
```

> 不再支持通过构造函数传入页面列表。请使用 `setData`、`add`、`insert` 等方法维护数据。

## 批量设置数据

### `setData(views)`

替换全部页面，标题会自动补齐为空标题。

```lua
adapter.setData(viewList)
```

### `setData(views, titles)`

替换全部页面和标题。标题数量会自动裁剪或补齐，`nil` 标题会转为空字符串。

```lua
adapter.setData(viewList, titleList)
```

## 添加页面

### `add(view)`

添加一个页面，标题为空字符串。

```lua
adapter.add(pageView)
```

### `add(view, title)`

添加一个带标题的页面。

```lua
adapter.add(pageView, "首页")
```

## 插入页面

### `insert(index, view)`

在指定 0 基索引处插入页面，标题为空字符串。索引越界时不会修改数据。

```lua
adapter.insert(0, pageView)
```

### `insert(index, view, title)`

在指定 0 基索引处插入带标题页面。索引越界时不会修改数据。

```lua
adapter.insert(1, pageView, "设置")
```

## 替换页面

### `set(index, view)`

替换指定页面并保留原标题。索引越界时不会修改数据。

```lua
adapter.set(0, newPageView)
```

### `set(index, view, title)`

替换指定页面和标题。索引越界时不会修改数据。

```lua
adapter.set(0, newPageView, "新标题")
```

## 移除页面

### `remove(index)`

移除指定 0 基索引的页面和对应标题，并返回被移除的 `View`。索引越界时返回 `nil`。

```lua
local removed = adapter.remove(0)
```

### `remove(view)`

移除指定 `View` 及其对应标题，返回是否成功移除。

```lua
local page = adapter.getItem(0)
local ok = adapter.remove(page)
```

## 清空页面

### `clear()`

清空所有页面和标题。

```lua
adapter.clear()
```

## 查询数据

### `getItem(index)`

获取指定 0 基索引的页面 `View`。

```lua
local page = adapter.getItem(0)
```

### `getCount()`

返回页面数量。

```lua
local count = adapter.getCount()
```

### `getPageTitle(position)`

返回指定位置标题。无标题或索引无效时返回空字符串。

```lua
local title = adapter.getPageTitle(0)
```

### `getData()`

返回内部页面 `List<View>`。

```lua
local views = adapter.getData()
```

### `getTitles()`

返回内部标题 `List<String>`。

```lua
local titles = adapter.getTitles()
```

## 布局表快捷属性

### `pages`

```lua
{
    ViewPager,
    id = "pager",
    pages = { page1View, page2View },
}
```

### `pagesWithTitle`

```lua
{
    ViewPager,
    id = "pager",
    pagesWithTitle = {
        { page1View, page2View },
        { "首页", "设置" },
    },
}
```

# `LuaPagerAdapter` API 文档 

提供一个自定义的 `PagerAdapter` 实现，方便在 LuaJ+ 中使用，用于轻松管理 Android `ViewPager` 中的页面 (View)。它简化了动态添加、移除和管理页面的过程。

也可以通过在布局表中给 `ViewPager` 设置 `pages` 或 `pagesWithTitle` 来自动创建 `LuaPagerAdapter`

## 导入类

使用 `LuaPagerAdapter` 前，首先需要导入该类：

```lua
-- 导入 LuaPagerAdapter 类
local LuaPagerAdapter = luajava.bindClass("github.daisukiKaffuChino.LuaPagerAdapter")

-- 导入必要的 Android 类
local ArrayList = luajava.bindClass("java.util.ArrayList")
local View = luajava.bindClass("android.view.View")
-- 根据需要导入其他类 (例如 TextView, Button, ViewPager 等)
```

## 描述

`LuaPagerAdapter` 继承自 `androidx.viewpager.widget.PagerAdapter`。它内部维护一个 `View` 对象的列表 (`List<View>`)，每个 View 代表 `ViewPager` 中的一个页面。它还可以选择性地管理一个对应的 `String` 标题列表 (`List<String>`)，可供 `TabLayout` 等组件使用以显示页面标题。

该适配器在进行修改操作（添加、插入、移除）后会自动调用 `notifyDataSetChanged()` 来更新 `ViewPager`。

**重要索引说明：** 所有接受或返回索引（`index` 或 `position`）的方法（如 `insert`, `remove`, `getItem`, `getPageTitle`）都使用 **基于 0 的索引**，这与 Java List 和 Android Adapter 的约定一致，即使 Lua 表通常是基于 1 的。从 Lua 调用这些方法时请务必注意这一点。

## 构造函数

### 1. `LuaPagerAdapter(views)`

创建一个只包含视图列表的 `LuaPagerAdapter`。页面标题将默认为 "No Title"。

*   **参数:**
    *   `views`: `List<View>` - 一个包含各页面 View 对象的 Java 列表。可以使用 `ArrayList` 创建。
*   **Lua 示例:**
    ```lua
    -- 实际上 LuaJ 可以将表自动转为 ArrayList
    local viewList = ArrayList()
    -- 向 viewList 添加 View 对象...
    local adapter = LuaPagerAdapter(viewList)
    ```

### 2. `LuaPagerAdapter(views, titles)`

创建一个同时包含视图列表和对应标题列表的 `LuaPagerAdapter`。

*   **参数:**
    *   `views`: `List<View>` - 包含页面 View 对象的 Java 列表。
    *   `titles`: `List<String>` - 包含页面标题 String 的 Java 列表。其大小最好与 `views` 列表匹配。如果传入 `nil`，内部会使用一个空列表。
*   **Lua 示例:**
    ```lua
    local viewList = ArrayList()
    local titleList = ArrayList()
    -- 向 viewList 和 titleList 添加 View 和对应的 String...
    local adapter = LuaPagerAdapter(viewList, titleList)
    ```

## 方法

### `add(view)`

将一个 `View` 添加到页面列表的末尾。

*   **参数:**
    *   `view`: `View` - 要添加为新页面的视图。
*   **返回值:** `void`
*   **Lua 示例:**
    ```lua
    local newView = TextView(activity)
    adapter.add(newView) -- 假设 'adapter' 是 LuaPagerAdapter 实例
    ```

### `add(view, title)`

将一个 `View` 及其对应的 `String` 标题添加到列表末尾。

*   **参数:**
    *   `view`: `View` - 要添加的视图。
    *   `title`: `String` - 新页面的标题。
*   **返回值:** `void`
*   **Lua 示例:**
    ```lua
    local newView = TextView(activity)
    adapter.add(newView, "新页面标题")
    ```

### `insert(index, view)`

在指定位置（基于 0 的索引）插入一个 `View`。

*   **参数:**
    *   `index`: `int` - 要插入视图的基于 0 的位置。
    *   `view`: `View` - 要插入的视图。
*   **返回值:** `void`
*   **Lua 示例:**
    ```lua
    local insertedView = TextView(activity)
    adapter.insert(0, insertedView) -- 插入到列表开头 (索引 0)
    ```

### `insert(index, view, title)`

在指定位置（基于 0 的索引）插入一个 `View` 及其 `String` 标题。

*   **参数:**
    *   `index`: `int` - 要插入的基于 0 的位置。
    *   `view`: `View` - 要插入的视图。
    *   `title`: `String` - 插入页面的标题。
*   **返回值:** `void`
*   **Lua 示例:**
    ```lua
    local insertedView = TextView(activity)
    adapter.insert(1, insertedView, "插入的标题") -- 插入到第二个位置 (索引 1)
    ```

### `remove(index)`

移除指定位置（基于 0 的索引）的页面（包括 View 和对应的标题，如果存在）。

*   **参数:**
    *   `index`: `int` - 要移除的页面的基于 0 的索引。
*   **返回值:** `View` - 被移除的 View 对象。
*   **Lua 示例:**
    ```lua
    local removedView = adapter.remove(0) -- 移除第一个页面 (索引 0)
    ```

### `remove(view)`

从页面列表中移除指定的 `View` 对象。**注意：此方法仅移除 View，不会自动移除对应的标题（如果存在）。**

*   **参数:**
    *   `view`: `View` - 要移除的确切 View 对象。
*   **返回值:** `boolean` - 如果找到并成功移除了视图，则返回 `true`，否则返回 `false`。
*   **Lua 示例:**
    ```lua
    local viewToRemove = adapter.getItem(1) -- 获取索引为 1 的视图
    if viewToRemove then adapter.remove(viewToRemove) end
    ```

### `getItem(index)`

获取指定位置（基于 0 的索引）的 `View` 对象。

*   **参数:**
    *   `index`: `int` - 所需页面的基于 0 的索引。
*   **返回值:** `View` - 指定索引处的 View 对象，如果索引越界则返回 `nil`。
*   **Lua 示例:**
    ```lua
    local pageView = adapter.getItem(1) -- 获取第二个页面的视图 (索引 1)
    ```

### `getCount()`

返回适配器当前管理的页面总数。

*   **参数:** 无
*   **返回值:** `int` - 页面数量。
*   **Lua 示例:**
    ```lua
    local count = adapter.getCount()
    print("总页数: " .. count)
    ```

### `getPageTitle(position)`

返回指定位置（基于 0 的索引）的页面标题。此方法主要供 `TabLayout` 等组件内部使用。

*   **参数:**
    *   `position`: `int` - 页面的基于 0 的索引。
*   **返回值:** `CharSequence` (在 Lua 中通常作为 `String` 处理) - 页面的标题，如果无标题或索引无效，则返回 "No Title"。
*   **Lua 示例 (直接调用较少见):**
    ```lua
    local title = adapter.getPageTitle(0) -- 获取第一个页面的标题
    ```

### `getData()`

返回包含所有页面视图的底层 Java `List<View>`。

*   **参数:** 无
*   **返回值:** `List<View>` - 包含所有视图的 Java 列表。
*   **Lua 示例:**
    ```lua
    local allViewsList = adapter.getData()
    local size = allViewsList.size() -- 获取列表大小
    ```
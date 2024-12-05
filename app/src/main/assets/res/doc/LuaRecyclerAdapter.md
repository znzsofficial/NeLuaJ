## LuaRecyclerAdapter
仿照 LuaAdapter 实现的RecyclerView Adapter，支持动态绑定 LuaTable 数据和布局，通过灵活的接口和默认逻辑实现高效的绑定操作。

使用时请手动导入 `com.androlua.adapter.LuaRecyclerAdapter`

---

## 构造函数

```java
LuaRecyclerAdapter(LuaContext context, LuaTable layout) throws LuaError
LuaRecyclerAdapter(LuaContext context, LuaTable data, LuaTable layout) throws LuaError
```
- **参数**:
    - `LuaContext context`: 当前 Lua 环境。
    - `LuaTable data`: 数据表，可选。
    - `LuaTable layout`: 布局表。
- **功能**: 初始化适配器，将 Lua 数据和布局表加载到适配器中。

---

## 方法

### 1. `setDataBinder(DataBinder binder)`
```java
public void setDataBinder(DataBinder binder)
```
- **参数**:
    - `DataBinder binder`: 自定义数据绑定器，负责将数据绑定到视图。
- **功能**: 设置自定义的数据绑定逻辑。如果未设置，将使用默认绑定逻辑（见下方）。

---

### 2. `add(LuaTable item)`
```java
public void add(LuaTable item)
```
- **参数**:
    - `LuaTable item`: 要添加的单项数据。
- **功能**: 向数据集添加一项，并更新界面。

---

### 3. `addAll(LuaTable items)`
```java
public void addAll(LuaTable items) throws Exception
```
- **参数**:
    - `LuaTable items`: 包含多个数据项的表。
- **功能**: 添加多个数据项，并批量更新界面。

---

### 4. `insert(int position, LuaTable item)`
```java
public void insert(int position, LuaTable item) throws Exception
```
- **参数**:
    - `int position`: 插入位置。
    - `LuaTable item`: 要插入的单项数据。
- **功能**: 在指定位置插入数据，并更新界面。

---

### 5. `remove(int position)`
```java
public void remove(int position) throws Exception
```
- **参数**:
    - `int position`: 要移除的项位置。
- **功能**: 移除指定位置的数据项，并更新界面。

---

### 6. `clear()`
```java
public void clear()
```
- **功能**: 清空数据集，并刷新界面。

---

### 7. `setNotifyOnChange(boolean notifyOnChange)`
```java
public void setNotifyOnChange(boolean notifyOnChange)
```
- **参数**:
    - `boolean notifyOnChange`: 是否在数据变化时自动通知界面更新。
- **功能**: 设置数据变化后的通知模式。

---

### 默认绑定逻辑
如果未通过 `setDataBinder` 设置自定义数据绑定器，则 `LuaRecyclerAdapter` 使用以下默认逻辑：

1. **数据表检查**: 从 `mData` 获取当前 `position` 对应的 `LuaTable`。
    - 如果 `item` 是一个 `LuaTable`，则提取其键值对。

2. **绑定数据**: 遍历数据表中的每个字段，将数据绑定到对应的视图（通过 `holder.holder` 获取）。
    - **支持的视图类型**:
        - `TextView`: 设置文本内容。
        - `ImageView`: 加载图片（支持字符串 URL、位图、Drawable 等）。
    - **支持的数据类型**:
        - 字符串 (`String`)
        - 数字 (`Number`)
        - 图片资源 (`Bitmap`, `Drawable`, `URL` 等)
        - 嵌套的 `LuaTable`（递归绑定）。

3. **辅助方法 (`setHelper`)**: 处理具体视图与数据的绑定逻辑。

### 默认绑定示例
假设 `LuaTable` 数据如下：
```lua
{
  title = "Hello, World!",
  image = "https://example.com/image.jpg",
  card = {
      onClick = function(view)
          print("Card clicked!")
      end
  }
}
```
且布局文件包含：
- 一个 ID 为 `title` 的 `TextView`。
- 一个 ID 为 `image` 的 `ImageView`。
- 一个 ID 为 `card` 的 `CardView`。

默认绑定逻辑会：
1. 将 `title` 字段设置为 `TextView` 的文本内容。
2. 使用图片加载器将 `image` 字段的 URL 加载到 `ImageView` 中。
3. 为 `card` 绑定一个点击事件，点击时打印 "Card clicked!"。

### 自定义绑定示例
```lua
adapter.dataBinder = function(views, item)
    views.title.text = item.title
end
```
- **参数**:
    - `views table`: 存放视图的表
    - `item table`: 当前项的数据
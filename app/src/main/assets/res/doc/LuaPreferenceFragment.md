## 📘 `LuaPreferenceFragment`

`LuaPreferenceFragment` 基于 `androidx.preference.PreferenceFragmentCompat` 实现。

### 📦 引入

在使用前，请确保已正确引入该类及其相关依赖，例如：

```lua
import "com.androlua.LuaPreferenceFragment"
import "androidx.preference.*"
```

### 🔧 构造函数

```lua
fragment = LuaPreferenceFragment(preferenceTable)
```

* `preferenceTable`：一个 LuaTable 表，定义所有 Preference 项。

示例结构：

```lua
local prefs = {
  {
    PreferenceCategory,  -- 第一项必须是 Preference 类
    title = "设置分类"
  },
  {
    EditTextPreference,
    key = "username",
    title = "用户名",
    summary = "请输入用户名",
    defaultValue = "guest"
  }
}

fragment = LuaPreferenceFragment(prefs)
```

### 🔁 方法说明

#### 🧩 `setPreference(preferenceTable)`

更新 fragment 使用的配置项。

```lua
fragment.setPreference(newPrefs)
```

#### 🔔 `setOnPreferenceChangeListener(listener)`

设置监听器函数，当某项 Preference 值被更改时触发。

```lua
fragment.setOnPreferenceChangeListener(function(preference, newValue)
  print("Preference changed:", preference, newValue)
  return true -- 返回 true 表示接受更改
end)
```

#### 🖱 `setOnPreferenceClickListener(listener)`

设置点击监听器，当某项 Preference 被点击时触发（适用于非可编辑类如 Switch、Category 等）。

```lua
fragment.setOnPreferenceClickListener(function(preference)
  print("Clicked:", preference.getKey())
  return true
end)
```

### 🧰 Preference 表定义说明

每一个子表代表一个 Preference 对象：

```lua
{
  PreferenceClass, -- 必填，Preference 类型
  key = "your_key", 
  title = "显示标题", 
  summary = "描述文本",
  defaultValue = "默认值",
  -- 其他属性根据实际 Preference 类型而定
}
```

可用的 `Preference` 类型：

* `Preference`
* `EditTextPreference`
* `CheckBoxPreference`
* `SwitchPreferenceCompat`
* `PreferenceCategory`
* `ListPreference` 等

### 📝 使用示例

```lua
import "com.androlua.LuaPreferenceFragment"
import "androidx.preference.SeekBarPreference"
import "androidx.preference.SwitchPreference"
local fragment = LuaPreferenceFragment{
    {
        SwitchPreference,
        defaultValue=true;
        title="开关";
        summary="描述";
        key="key_preference";
    },
    {
        SeekBarPreference,
        value=5,
    }
}
this.setFragment(fragment)

fragment.onPreferenceChange = function(preference, newValue)
    print(preference, newValue)
end

fragment.onPreferenceClick = function(preference)
    print(preference)
end
```
# Migration Guide

This document helps you migrate older NeLuaJ+ projects to the latest version, which introduces **Material 3 Expressive** design.

---

## 1. Status Bar

### Recommended Pattern

Use the following pattern to properly handle status bar colors for light/dark mode:

```lua
import "android.view.View"
import "android.view.WindowManager"

local ColorUtil = this.themeUtil

local window = activity.getWindow()
    .setNavigationBarColor(0)
    .setStatusBarColor(ColorUtil.getColorBackground())
    .addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    .clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end
```

> **Tip**: When using ActionBar theme (`Theme_NeLuaJ_Material3`), the ActionBar handles status bar automatically. Manual setup is only needed for NoActionBar themes.

---

## 2. Theme Migration

### Recommended Themes

| Theme | Description |
|-------|-------------|
| `Theme_NeLuaJ_Material3` | With ActionBar, for simple pages |
| `Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay` | No ActionBar, for custom Toolbar pages |

### Theme Setup

**Option 1 (Recommended)**: Set in `init.lua`, applied automatically:

```lua
-- init.lua
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
```

**Option 2**: Set manually in `main.lua` (must be before `setContentView`):

```lua
activity.setTheme(R.style.Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay)
```

### Dynamic Colors

Call `activity.dynamicColor()` in `onCreate` to enable Material You dynamic theming:

```lua
activity.dynamicColor()
```

---

## 3. Component Migration

### Recommended Material 3 Components

| Old | New | Notes |
|-----|-----|-------|
| `TextView` | `MaterialTextView` | MD3 text styles |
| `Button` | `MaterialButton` | MD3 button styles |
| `EditText` | `TextInputEditText` + `TextInputLayout` | MD3 input fields |
| `CardView` | `MaterialCardView` | Stroke, corner radius |
| `Toolbar` | `MaterialToolbar` | MD3 toolbar |

### Color Access

Use `LuaThemeUtil` instead of hardcoded colors:

```lua
local ColorUtil = this.themeUtil

-- Recommended: structured access
local primary = ColorUtil.primary.main
local surface = ColorUtil.surface.main

-- Legacy: method access
local primary = ColorUtil.getColorPrimary()
local background = ColorUtil.getColorBackground()
```

### Size Units

- Use **`sp`** for text sizes (respects system font scaling)
- Use **`dp`** for spacing and dimensions
- ❌ Never use `dp` for text sizes

---

## 4. init.lua Configuration Update

### Recommended Configuration

```lua
app_name = "My App"
package_name = "com.example.myapp"
ver_name = "1.0"
ver_code = "1"
min_sdk = "26"        -- Android 8.0 (was 21)
target_sdk = "33"     -- Android 13 (was 29)
debug_mode = true
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
user_permission = {
  "INTERNET",
}
```

### Changes

| Config | Old Default | New Default | Reason |
|--------|------------|-------------|--------|
| `min_sdk` | `21` | `26` | Android 8.0 below has minimal market share |
| `target_sdk` | `29` | `33` | Android 13 permission model |
| `user_permission` | Includes `WRITE_EXTERNAL_STORAGE` | Only `INTERNET` | Not needed on Android 13+ |

---

## 5. FAQ

### Q: Status bar icons invisible in dark mode?

A: Make sure you set `setSystemUiVisibility` based on `isNightMode()`:

```lua
if this.isNightMode() then
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
else
    window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
end
```

### Q: How to match status bar color with ActionBar?

A: Set `setStatusBarColor` to the same background color:

```lua
activity.getWindow().setStatusBarColor(ColorUtil.getColorBackground())
```

### Q: How to achieve full immersive mode (e.g. image viewer)?

A: Use the following to extend content behind system bars:

```lua
pcall(function()
    local window = activity.getWindow()
    window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    window.getDecorView().setSystemUiVisibility(
        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR)
    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    window.setStatusBarColor(Color.TRANSPARENT)
    window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
end)
```

### Q: How to get theme colors instead of hardcoding?

A: Use `this.themeUtil` (see LuaThemeUtil docs):

```lua
local ColorUtil = this.themeUtil
local bg = ColorUtil.getColorBackground()
local primary = ColorUtil.primary.main
local onSurface = ColorUtil.surface.on
```

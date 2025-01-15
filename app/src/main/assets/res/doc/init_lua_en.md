# `init.lua` Configuration File Documentation

The `init.lua` file is used to configure the application's environment parameters. It is a Lua script containing various variables that control settings such as the application name, version, debug mode, theme, and more. It is recommended to use the official builder to generate the script to avoid manually editing `init.lua`.

## Structure of `init.lua`

The file should define variables to configure the application's behavior. Below is a description of the supported variables:

---

## **1. `app_name`**
- **Type**: `string`
- **Description**: Specifies the name of the application, which will be displayed as the application window title.

### Example:
```lua
app_name = "Sample Application"
```

---

## **2. `package_name`**
- **Type**: `string`
- **Description**: Defines the application's package name, which is used to uniquely identify the application. Ensure the package name follows standard naming conventions, such as `com.example.myapp`.

### Example:
```lua
package_name = "com.example.myapp"
```

---

## **3. `ver_name`**
- **Type**: `string`
- **Description**: The version name of the application, typically shown to users, such as `1.0.0`.

### Example:
```lua
ver_name = "1.0.0"
```

---

## **4. `ver_code`**
- **Type**: `integer`
- **Description**: The version code of the application, usually an incrementing integer used to identify the build version.

### Example:
```lua
ver_code = 101
```

---

## **5. `debug_mode`**
- **Type**: `boolean`
- **Description**: Enables or disables debug mode. When debug mode is enabled, the application may produce additional debug logs to help developers troubleshoot issues.

### Example:
```lua
debug_mode = true
```

---

## **6. `target_sdk`**
- **Type**: `integer`
- **Description**: Specifies the target SDK version, indicating the version of the SDK the application is designed to run on. It is recommended to align this with the project's build configuration.

### Example:
```lua
target_sdk = 33
```

---

## **7. `min_sdk`**
- **Type**: `integer`
- **Description**: Specifies the minimum SDK version, indicating the lowest version of Android supported by the application.

### Example:
```lua
min_sdk = 24
```

---

## **8. `NeLuaJ_Theme`**
- **Type**: `string`
- **Description**: Defines the application's theme name. This theme should match a theme field defined in the `R.style` class.

### Example:
```lua
NeLuaJ_Theme = "Theme_NeLuaJ_Material3"
```

---

## **9. `theme`** *(Deprecated)*
- **Type**: `integer` or `string`
- **Description**: Configures the application's theme. This field is marked as deprecated, and it is recommended to use `NeLuaJ_Theme` instead. If a number is provided, it directly represents the theme resource ID. If a string is provided, it should match a theme field name in the `android.R.style` class.

### Example:
```lua
theme = "Theme_Material_Light"
```

---

## **10. `user_permission`**
- **Type**: `table` (array format)
- **Description**: Defines the list of permissions required by the application. These permissions should be listed as strings and comply with Android's standard permission definitions.

### Example:
```lua
user_permission = { "android.permission.INTERNET", "android.permission.CAMERA" }
```

---

## Example `init.lua` File

Below is a sample configuration file demonstrating how to define all supported variables:

```lua
app_name = "Sample Application"
package_name = "com.example.myapp"
ver_name = "1.0.0"
ver_code = 101
debug_mode = true
target_sdk = 33
min_sdk = 24
NeLuaJ_Theme = "Theme_NeLuaJ_Material3"
theme = "Theme_Material_Light" -- Deprecated
user_permission = { "android.permission.INTERNET", "android.permission.CAMERA" }
```

---

## Notes
1. **Project Directory Requirement**: Ensure the `init.lua` file is located in the root directory of the project.
2. **Syntax Accuracy**: Syntax errors in the `init.lua` file may result in loading failures. It is recommended to verify the file's syntax after editing.
3. **Permission Configuration**: Permissions in `user_permission` must adhere to Android's standard permission definitions to ensure proper functionality.
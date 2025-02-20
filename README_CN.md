<div align="center">

----
[![CI](https://github.com/znzsofficial/NeLuaJ/actions/workflows/android.yml/badge.svg?event=push)](https://github.com/znzsofficial/NeLuaJ/actions/workflows/gradle.yml)
[![GitHub license](https://img.shields.io/github/license/znzsofficial/NeLuaJ)](https://github.com/znzsofficial/NeLuaJ/blob/main/LICENSE)
[![QQ](https://img.shields.io/badge/Join-QQ_Group-ff69b4)](https://qm.qq.com/cgi-bin/qm/qr?k=Y4DCrLhx2bie5LaLF4msQOHLVY1s7EeN&jump_from=webapi&authKey=KV3sOndkaiImC7LZB3Rt37sCOyRG3akbzURt+4GyQXps2x1EkyCQl7D3+16GQXyE)

NeLuaJ+是一款Android的LuaJ IDE

</div>

## **前言**
本项目适合具有一定 Android 开发基础的用户。如果以下情况让你感到困惑，建议谨慎使用：
- 编辑器未自带中文或模板。
- 从其他编辑器复制的代码无法运行。
- 对编程仅有浅层次接触（如仅通过QQ群或小论坛了解编程）。


# 功能亮点与更新说明

## **值得注意的更新**
### **1. 配置与主题**
- 新增 `init.lua` 中的 **NeLuaJ_Theme** 配置，允许直接设置编辑器内置主题。

### **2. 布局支持**
- `setContentView` 方法支持以下两种参数：
    - 传入布局表。
    - 加载过的视图对象。

### **3. 新增功能与优化**
- **`LuaActivity`**:
    - 完善 `AppCompatActivity` 的继承方法，支持更多新特性。
- **`LuaFragment`**:
    - 添加更多方法。
    - 迁移至 **AndroidX** 框架。

---

## **重要变更**
1. **权限申请逻辑更新**：
    - `Welcome` 不再自动申请全部权限，符合 Android 运行时权限设计要求。
    - 请开发者自行实现权限申请及回调逻辑。

2. **多线程优化**：
    - `Welcome` 使用多线程解压，并在过程中将 `assets` 中的所有 `dex` 文件设置为只读。

3. **功能移除**：
    - 删除了内置的 `android.widget` 包。
    - 移除了与 `PageView` 相关的适配器。

---

# 新特性与扩展支持

## **1. 图片加载功能**
将部分适配器移动至 **`com.androlua.adapter`** 包，并引入 **Coil** 实现图片加载，提供更强大的图片处理能力。

## **2. 导入分析工具**
实现类似 **FusionApp2** 的导入分析功能，支持更高效的资源管理。
- **作者信息**: [QQ: 3070320289](#)。

## **3. 布局助手**
- **作者信息**: [QQ: 2241056127](#)。

---

<div align="center">

# NeLuaJ+

----
[![CI](https://github.com/znzsofficial/NeLuaJ/actions/workflows/gradle.yml/badge.svg?event=push)](https://github.com/znzsofficial/NeLuaJ/actions/workflows/gradle.yml)
[![GitHub license](https://img.shields.io/github/license/znzsofficial/NeLuaJ)](https://github.com/znzsofficial/NeLuaJ/blob/main/LICENSE)
[![QQ](https://img.shields.io/badge/Join-QQ_Group-ff69b4)](https://qm.qq.com/cgi-bin/qm/qr?k=Y4DCrLhx2bie5LaLF4msQOHLVY1s7EeN&jump_from=webapi&authKey=KV3sOndkaiImC7LZB3Rt37sCOyRG3akbzURt+4GyQXps2x1EkyCQl7D3+16GQXyE)

NeLuaJ+ is a LuaJ IDE for Android

</div>


## **Other Languages**
- **[简体中文](README_CN.md)**: Click here for the Simplified Chinese version of this document.


# Feature Highlights and Update Notes

## **Noteworthy Updates**
### **1. Configuration and Themes**
- Added **NeLuaJ_Theme** configuration in `init.lua`, allowing direct setup of built-in editor themes.

### **2. Layout Support**
- The `setContentView` method now supports two types of parameters:
    - Passing a layout table.
    - Using a preloaded view object.

### **3. New Features and Optimizations**
- **`LuaActivity`**:
    - Improved inheritance of `AppCompatActivity`, supporting more new features.
- **`LuaFragment`**:
    - Added more methods.
    - Migrated to the **AndroidX** framework.

---  

## **Important Changes**
1. **Permission Request Logic Update**:
    - `Welcome` no longer automatically requests all permissions, aligning with Android runtime permission requirements.
    - Developers are responsible for implementing permission requests and callback logic.

2. **Multithreading Optimization**:
    - `Welcome` uses multithreading for decompression and sets all `dex` files in `assets` to read-only during the process.

3. **Feature Removal**:
    - Removed the built-in `android.widget` package.
    - Removed adapters related to `PageView`.

---  

# New Features and Extended Support

## **1. Image Loading**
Moved some adapters to the **`com.androlua.adapter`** package and introduced **Coil** for image loading, providing enhanced image processing capabilities.

## **2. Import Analysis Tool**
Implemented an import analysis feature similar to **FusionApp2**, enabling more efficient resource management.
- **Author Info**: [QQ: 3070320289](#).

## **3. Layout Assistant**
- **Author Info**: [QQ: 2241056127](#).

---  
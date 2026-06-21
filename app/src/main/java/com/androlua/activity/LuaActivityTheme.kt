package com.androlua.activity

import android.content.res.Configuration
import android.graphics.BlendMode
import android.graphics.BlendModeColorFilter
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.os.Build
import com.androlua.LuaActivity
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.DynamicColorsOptions
import com.google.android.material.color.MaterialColors

class LuaActivityTheme(private val activity: LuaActivity) {
    
    fun isNightMode() =
        (activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    
    fun getFilter(color: Int): ColorFilter {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            BlendModeColorFilter(color, BlendMode.SRC_ATOP)
        } else {
            PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP)
        }
    }
    
    fun dynamicColor() {
        when (val seedColor = activity.getSharedData("theme_seed_color")) {
            is Int -> dynamicColor(seedColor)
            is Long -> dynamicColor(seedColor.toInt())
            is String -> {
                if (seedColor.isNotBlank()) {
                    runCatching { Color.parseColor(seedColor) }
                        .onSuccess { dynamicColor(it) }
                        .onFailure { DynamicColors.applyToActivityIfAvailable(activity) }
                } else {
                    DynamicColors.applyToActivityIfAvailable(activity)
                }
            }
            else -> DynamicColors.applyToActivityIfAvailable(activity)
        }
    }
    
    /**
     * Apply dynamic colors based on a seed color.
     * Generates a full Material 3 color scheme from the given seed color
     * and applies it to the Activity. After calling this, themeUtil will
     * reflect the new color scheme.
     *
     * Usage in Lua: this.dynamicColor(0xFF6750A4)
     */
    fun dynamicColor(seedColor: Int) {
        val options = DynamicColorsOptions.Builder()
            .setContentBasedSource(seedColor)
            .build()
        DynamicColors.applyToActivityIfAvailable(activity, options)
    }
    
    /**
     * Harmonize a color with the current theme's primary color.
     * Returns a new color that is visually harmonious with the theme.
     *
     * Usage in Lua: local harmonized = this.harmonizeColor(0xFFFF0000)
     */
    fun harmonizeColor(color: Int): Int =
        MaterialColors.harmonizeWithPrimary(activity, color)
    
    /**
     * Harmonize two arbitrary colors.
     *
     * Usage in Lua: local result = this.harmonizeColor(color1, color2)
     */
    fun harmonizeColor(color: Int, withColor: Int): Int =
        MaterialColors.harmonize(color, withColor)
    
    /**
     * Check if a color is considered light.
     *
     * Usage in Lua: local light = this.isColorLight(0xFFFFFFFF)
     */
    fun isColorLight(color: Int): Boolean =
        MaterialColors.isColorLight(color)
}
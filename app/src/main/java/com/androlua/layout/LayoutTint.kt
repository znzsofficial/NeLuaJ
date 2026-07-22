package com.androlua.layout

import android.content.res.ColorStateList
import android.view.View
import android.widget.CompoundButton
import android.widget.ImageView
import android.widget.ProgressBar
import androidx.core.view.ViewCompat
import androidx.core.widget.CompoundButtonCompat
import androidx.core.widget.ImageViewCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.textfield.TextInputLayout

/**
 * 工程历史属性 TintColor：按控件类型落到强调/图标/按钮 tint。
 */
internal object LayoutTint {

    fun apply(host: View, csl: ColorStateList) {
        when (host) {
            is ImageView -> {
                ImageViewCompat.setImageTintList(host, csl)
                if (host is FloatingActionButton) {
                    host.backgroundTintList = csl
                }
            }
            is CompoundButton -> {
                CompoundButtonCompat.setButtonTintList(host, csl)
                LayoutReflection.invokeColorStateListSetter(host, "setTrackTintList", csl)
                LayoutReflection.invokeColorStateListSetter(host, "setThumbTintList", csl)
            }
            is ProgressBar -> {
                host.indeterminateTintList = csl
                host.progressTintList = csl
                host.secondaryProgressTintList = csl
            }
            is MaterialButton -> {
                host.backgroundTintList = csl
                host.iconTint = csl
            }
            is ExtendedFloatingActionButton -> {
                host.backgroundTintList = csl
                host.iconTint = csl
            }
            is Chip -> {
                host.chipIconTint = csl
                host.closeIconTint = csl
            }
            is TextInputLayout -> {
                host.setBoxStrokeColorStateList(csl)
                host.setHintTextColor(csl)
                host.setStartIconTintList(csl)
                host.setEndIconTintList(csl)
            }
            is MaterialCardView -> host.setStrokeColor(csl)
            else -> {
                ViewCompat.setBackgroundTintList(host, csl)
                if (!LayoutReflection.invokeColorStateListSetter(
                        host, "setSupportBackgroundTintList", csl
                    )
                ) {
                    LayoutReflection.invokeColorStateListSetter(host, "setButtonTintList", csl)
                    LayoutReflection.invokeColorStateListSetter(host, "setIconTintList", csl)
                    LayoutReflection.invokeColorStateListSetter(host, "setImageTintList", csl)
                }
            }
        }
    }
}

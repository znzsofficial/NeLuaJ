package com.nekolaksa.material

import android.content.Context
import android.util.AttributeSet
import android.widget.HorizontalScrollView
import androidx.annotation.StyleRes
import androidx.appcompat.view.ContextThemeWrapper
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup

class ChipTabLayout @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : HorizontalScrollView(context, attrs) {
    private val chipGroup = ChipGroup(context)

    init {
        isHorizontalScrollBarEnabled = false
        addView(chipGroup.apply {
            isSingleSelection = true
            isSingleLine = true
            isSelectionRequired = true
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        })
    }

    private fun chipWithStyle(context: Context, @StyleRes style: Int): Chip {
        return Chip(ContextThemeWrapper(context, style), null, style)
    }

    fun addChip(text: String) = Chip(context).apply {
        this.text = text
        isCheckable = true
        chipGroup.addView(this)
    }

    fun addChip(text: String, @StyleRes style: Int) = chipWithStyle(context, style).apply {
        this.text = text
        isCheckable = true
        chipGroup.addView(this)
    }

    fun selectChip(text: String) {
        val chip = findChipForText(text) ?: return
        chipGroup.check(chip.id)
    }

    fun selectChipAt(index: Int) {
        if (index < 0 || index >= chipGroup.childCount) return
        chipGroup.check(chipGroup.getChildAt(index).id)
    }

    private fun findChipForText(text: String): Chip? {
        for (i in 0..<chipGroup.childCount) {
            val chip = (chipGroup.getChildAt(i) as Chip)
            if (chip.text == text) {
                return chip
            }
        }
        return null
    }

    fun removeChip(text: String) {
        val chip = findChipForText(text) ?: return
        chipGroup.removeView(chip)
    }

    fun onSelected(listener: (Chip) -> Unit) {
        chipGroup.setOnCheckedStateChangeListener { _, list ->
            listener(chipGroup.findViewById<Chip>(list[0]))
        }
    }
}
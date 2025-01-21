package com.nekolaska.internal

import android.annotation.SuppressLint
import android.content.SharedPreferences

@SuppressLint("UseKtx")
inline fun SharedPreferences.commit(block: SharedPreferences.Editor.() -> Unit): Boolean {
    val editor = edit()
    editor.block()
    return editor.commit()
}
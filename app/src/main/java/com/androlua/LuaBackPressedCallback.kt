package com.androlua

import androidx.activity.OnBackPressedCallback
import org.luaj.LuaFunction

class LuaBackPressedCallback(private val function: LuaFunction) : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        function.call()
    }
}
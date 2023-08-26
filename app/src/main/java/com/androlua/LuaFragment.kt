package com.androlua

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import org.luaj.LuaError
import org.luaj.LuaTable
import org.luaj.LuaValue

@SuppressLint("ValidFragment")
class LuaFragment : Fragment {
    private var mLayout: LuaTable? = null
    private var mEnv: LuaTable? = null
    private var mView: View? = null

    constructor(layout: LuaTable?) {
        mLayout = layout
    }

    constructor(view: View?) {
        mView = view
    }

    constructor()

    fun setLayout(layout: LuaTable?) {
        mLayout = layout
    }

    fun setLayout(view: View?) {
        mView = view
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View? {
        return try {
            if (mView != null) {
                return mView
            }
            mEnv = LuaTable()
            LuaLayout(activity).load(mLayout, mEnv).touserdata(
                View::class.java
            )
        } catch (e: LuaError) {
            throw IllegalArgumentException(e.message)
        }
    }

    fun getView(id: String?): LuaValue? {
        return if (mEnv == null) null else mEnv!![id]
    }

    companion object {
        @JvmStatic
        fun newInstance(layout: LuaTable?): LuaFragment {
            return LuaFragment(layout)
        }
        @JvmStatic
        fun newInstance(view: View?): LuaFragment {
            return LuaFragment(view)
        }
    }
}

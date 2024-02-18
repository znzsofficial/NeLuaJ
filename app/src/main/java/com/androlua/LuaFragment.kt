package com.androlua

import android.content.Context
import android.os.Bundle
import android.view.ContextMenu
import android.view.LayoutInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment

class LuaFragment(var creator: Creator?) : Fragment() {
    constructor() : this(null)

    companion object {
        @JvmStatic
        fun newInstance(creator: Creator): LuaFragment {
            val fragment = LuaFragment()
            fragment.creator = creator
            return fragment
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        creator?.onCreate(savedInstanceState)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return creator?.onCreateView(inflater, container, savedInstanceState)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        creator?.onViewCreated(view, savedInstanceState)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        creator?.onDestroyView()
    }

    override fun onCreateContextMenu(
        menu: ContextMenu,
        v: View,
        menuInfo: ContextMenu.ContextMenuInfo?
    ) {
        super.onCreateContextMenu(menu, v, menuInfo)
        creator?.onCreateContextMenu(menu, v, menuInfo)
    }

    override fun onContextItemSelected(item: MenuItem): Boolean {
        super.onContextItemSelected(item)
        return creator?.onContextItemSelected(item) ?: false
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        creator?.onSaveInstanceState(outState)
    }

    override fun onViewStateRestored(savedInstanceState: Bundle?) {
        super.onViewStateRestored(savedInstanceState)
        creator?.onViewStateRestored(savedInstanceState)
    }

    override fun onDestroy() {
        super.onDestroy()
        creator?.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        creator?.onResume()
    }

    override fun onStop() {
        super.onStop()
        creator?.onStop()
    }

    override fun onStart() {
        super.onStart()
        creator?.onStart()
    }

    override fun onAttach(context: Context) {
        super.onAttach(context)
        creator?.onAttach(context)
    }

    override fun onPause() {
        super.onPause()
        creator?.onPause()
    }

    interface Creator {
        fun onCreateView(
            inflater: LayoutInflater,
            container: ViewGroup?,
            savedInstanceState: Bundle?
        ): View?

        fun onDestroyView()
        fun onViewCreated(view: View, savedInstanceState: Bundle?)
        fun onResume()
        fun onPause()
        fun onAttach(context: Context)
        fun onStop()
        fun onStart()
        fun onDestroy()
        fun onSaveInstanceState(outState: Bundle)
        fun onViewStateRestored(savedInstanceState: Bundle?)
        fun onContextItemSelected(item: MenuItem): Boolean
        fun onCreateContextMenu(menu: ContextMenu, v: View, menuInfo: ContextMenu.ContextMenuInfo?)
        fun onCreate(savedInstanceState: Bundle?)
    }
}

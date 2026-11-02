package com.nekolaska.home

import android.os.Bundle
import android.os.Parcelable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import androidx.core.widget.NestedScrollView
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.RecyclerView
import com.androlua.LuaActivity

/** No retained Lua closure: FragmentManager can instantiate this class after process death. */
class HomePageFragment : Fragment() {
    private var pendingScroll: IntArray? = null
    private var pendingLists: Bundle? = null
    private var restoreListener: ViewTreeObserver.OnPreDrawListener? = null

    private val pageKey: String
        get() = requireArguments().getString(ARG_PAGE).also {
            require(it != null && HomePages.positionOf(it) >= 0) { "Invalid home page identity" }
        }!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        pendingScroll = pendingScroll ?: savedInstanceState?.getIntArray(STATE_SCROLL)
        pendingLists = pendingLists ?: savedInstanceState?.getBundle(STATE_LISTS)
        val root = (requireActivity() as LuaActivity).runFunc("__homeBuildPage", pageKey) as? View
            ?: error("Home host did not build $pageKey")
        root.id = 0x00d00000 + HomePages.positionOf(pageKey) * 0x10000
        // Stateful containers get deterministic IDs before Fragment restores the hierarchy.
        // Do not replace IDs on Lua-wired controls, or descend into recycled item views.
        var scrollIndex = 0
        visitStateful(root) { scroller ->
            scroller.id = root.id + 1 + scrollIndex++
            // Async adapter content is not available during normal hierarchy restoration.
            // Own LayoutManager state explicitly so a delayed hierarchy restore cannot overwrite it.
            if (scroller is RecyclerView) scroller.isSaveEnabled = false
        }
        return root
    }

    override fun onViewStateRestored(savedInstanceState: Bundle?) {
        super.onViewStateRestored(savedInstanceState)
        // Dynamic lists announce when their asynchronous content has been applied. Restoring an
        // empty ScrollView here would clamp its saved offset to zero before rows arrive.
        if (pageKey == "help" || pageKey == "settings") contentReady()
    }

    override fun onResume() {
        super.onResume()
        (requireActivity() as LuaActivity).runFunc("__homePageVisible", pageKey)
    }

    override fun onPause() {
        (requireActivity() as LuaActivity).runFunc("__homePausePage", pageKey)
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putIntArray(STATE_SCROLL, pendingScroll ?: view?.let(::captureScroll))
        outState.putBundle(STATE_LISTS, captureLists(view, pendingLists))
    }

    /** Called after a page has applied its rows, not merely after starting an IO job. */
    fun contentReady() {
        val root = view ?: return
        restoreLists(root)
        if (pendingScroll == null || restoreListener != null) return
        val listener = object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                root.viewTreeObserver.takeIf { it.isAlive }?.removeOnPreDrawListener(this)
                restoreListener = null
                if (view !== root) return true
                val values = pendingScroll ?: return true
                pendingScroll = null
                for (i in values.indices step 3) {
                    root.findViewById<View>(values[i])?.scrollTo(values[i + 1], values[i + 2])
                }
                return true
            }
        }
        restoreListener = listener
        root.viewTreeObserver.addOnPreDrawListener(listener)
        root.requestLayout()
        root.invalidate()
    }

    override fun onDestroyView() {
        if (pendingScroll == null) pendingScroll = view?.let(::captureScroll)
        pendingLists = captureLists(view, pendingLists)
        restoreListener?.let { listener ->
            view?.viewTreeObserver?.takeIf { it.isAlive }?.removeOnPreDrawListener(listener)
        }
        restoreListener = null
        (requireActivity() as LuaActivity).runFunc("__homeDisposePage", pageKey)
        super.onDestroyView()
    }

    @Suppress("DEPRECATION")
    private fun restoreLists(root: View) {
        val states = pendingLists ?: return
        states.classLoader = RecyclerView::class.java.classLoader
        visitStateful(root) { scroller ->
            if (scroller is RecyclerView && (scroller.adapter?.itemCount ?: 0) > 0) {
                val key = scroller.id.toString()
                val state = states.getParcelable<Parcelable>(key)
                if (state != null && scroller.layoutManager != null) {
                    scroller.layoutManager?.onRestoreInstanceState(state)
                    states.remove(key)
                    scroller.requestLayout()
                }
            }
        }
        if (states.isEmpty) pendingLists = null
    }

    companion object {
        private const val ARG_PAGE = "home.page_key"
        private const val STATE_SCROLL = "home.scroll_offsets"
        private const val STATE_LISTS = "home.recycler_states"

        @JvmStatic fun newInstance(key: String): HomePageFragment {
            require(HomePages.positionOf(key) >= 0) { "Unknown home page: $key" }
            return HomePageFragment().apply {
                arguments = Bundle().apply { putString(ARG_PAGE, key) }
            }
        }

        private fun captureScroll(root: View): IntArray {
            val values = ArrayList<Int>()
            visitStateful(root) {
                if (it !is RecyclerView) values.addAll(listOf(it.id, it.scrollX, it.scrollY))
            }
            return values.toIntArray()
        }

        private fun captureLists(root: View?, pending: Bundle?): Bundle {
            val states = pending?.let(::Bundle) ?: Bundle()
            if (root != null) visitStateful(root) {
                val key = it.id.toString()
                if (it is RecyclerView && !states.containsKey(key)) {
                    it.layoutManager?.onSaveInstanceState()?.let { state -> states.putParcelable(key, state) }
                }
            }
            return states
        }

        private fun visitStateful(view: View, action: (View) -> Unit) {
            if (view is ScrollView || view is HorizontalScrollView || view is NestedScrollView || view is RecyclerView) {
                action(view)
            }
            if (view is ViewGroup && view !is RecyclerView) {
                for (i in 0 until view.childCount) visitStateful(view.getChildAt(i), action)
            }
        }
    }
}

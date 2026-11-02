package com.nekolaska.home

import android.graphics.drawable.Drawable
import android.view.View
import android.widget.LinearLayout
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.viewpager2.adapter.FragmentStateAdapter
import androidx.viewpager2.widget.ViewPager2
import com.androlua.LuaActivity
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.navigation.NavigationBarView
import com.google.android.material.navigationrail.NavigationRailView

/** One pager instance across window changes. Android owns its selection and adapter saved state. */
class HomeShellView(private val host: LuaActivity) : LinearLayout(host) {
    val pager = ViewPager2(host)
    val bottomNav = BottomNavigationView(host)
    val rail = NavigationRailView(host)
    private var synchronizing = false
    private var disposed = false
    private var refreshPending = false
    private val refresh = Runnable {
        refreshPending = false
        if (disposed || !isAttachedToWindow || host.isFinishing || host.isDestroyed ||
            !host.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return@Runnable
        val key = HomePages.keyAt(pager.currentItem)
        val fragment = visibleFragment(key)
        // A later fragment onResume requests the refresh if its view is not ready yet.
        if (fragment?.isResumed == true && fragment.view != null) {
            host.runFunc("__homeRefreshPage", key)
        }
    }
    private val lifecycleObserver = object : DefaultLifecycleObserver {
        override fun onResume(owner: LifecycleOwner) = requestVisibleRefresh()
        override fun onPause(owner: LifecycleOwner) = cancelRefresh()
        override fun onDestroy(owner: LifecycleOwner) = dispose()
    }
    private val pageCallback = object : ViewPager2.OnPageChangeCallback() {
        override fun onPageSelected(position: Int) {
            syncSelection(position)
            requestVisibleRefresh()
        }
    }

    init {
        id = SHELL_ID
        orientation = VERTICAL
        pager.id = PAGER_ID
        pager.isUserInputEnabled = false
        pager.offscreenPageLimit = 1
        bottomNav.id = BOTTOM_ID
        rail.id = RAIL_ID
        for (nav in listOf<NavigationBarView>(bottomNav, rail)) {
            // The pager is the sole selection-state authority, not two conflicting saved menus.
            nav.isSaveEnabled = false
            nav.labelVisibilityMode = NavigationBarView.LABEL_VISIBILITY_LABELED
            nav.setOnItemSelectedListener { item ->
                if (!synchronizing) selectTab(item.itemId)
                true
            }
            nav.setOnItemReselectedListener { requestVisibleRefresh() }
        }
        val content = LinearLayout(host).apply { orientation = HORIZONTAL }
        rail.visibility = GONE
        content.addView(rail, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        content.addView(pager, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
        addView(content, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(bottomNav, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        pager.registerOnPageChangeCallback(pageCallback)
        host.lifecycle.addObserver(lifecycleObserver)
    }

    fun addDestination(key: String, title: String, drawable: Drawable?) {
        val position = HomePages.positionOf(key)
        require(position >= 0)
        for (nav in listOf<NavigationBarView>(bottomNav, rail)) {
            nav.menu.add(0, position + 1, position, title).setIcon(drawable)
        }
    }

    fun bindPages() {
        check(pager.adapter == null)
        pager.adapter = object : FragmentStateAdapter(host) {
            override fun getItemCount(): Int = HomePages.count()
            override fun getItemId(position: Int): Long = HomePages.idAt(position)
            override fun containsItem(itemId: Long): Boolean = HomePages.containsId(itemId)
            override fun createFragment(position: Int) =
                HomePageFragment.newInstance(HomePages.keyAt(position))
        }
        syncSelection(pager.currentItem)
    }

    /** 1-based compatibility with the original four bottom-menu item IDs. */
    fun selectTab(tab: Int) {
        if (disposed || tab !in 1..HomePages.count()) return
        pager.setCurrentItem(tab - 1, false)
        syncSelection(tab - 1)
        requestVisibleRefresh()
    }

    fun selectPage(key: String) {
        val position = HomePages.positionOf(key)
        if (position >= 0) selectTab(position + 1)
    }

    fun requestVisibleRefresh() {
        if (disposed || refreshPending) return
        refreshPending = true
        post(refresh)
    }

    fun pageContentReady(key: String) {
        if (!disposed) visibleFragment(key)?.contentReady()
    }

    private fun visibleFragment(key: String): HomePageFragment? =
        host.supportFragmentManager.fragments.filterIsInstance<HomePageFragment>()
            .firstOrNull { it.arguments?.getString("home.page_key") == key }

    private fun syncSelection(position: Int) {
        synchronizing = true
        try {
            bottomNav.selectedItemId = position + 1
            rail.selectedItemId = position + 1
        } finally {
            synchronizing = false
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val expanded = HomePages.useRail(w, resources.displayMetrics.density)
        rail.visibility = if (expanded) View.VISIBLE else View.GONE
        bottomNav.visibility = if (expanded) View.GONE else View.VISIBLE
    }

    private fun cancelRefresh() {
        removeCallbacks(refresh)
        refreshPending = false
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancelRefresh()
        pager.unregisterOnPageChangeCallback(pageCallback)
        host.lifecycle.removeObserver(lifecycleObserver)
    }

    companion object {
        private const val SHELL_ID = 0x00c40100
        private const val PAGER_ID = 0x00c40101
        private const val BOTTOM_ID = 0x00c40102
        private const val RAIL_ID = 0x00c40103
    }
}

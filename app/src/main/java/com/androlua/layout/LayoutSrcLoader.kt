package com.androlua.layout

import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.view.View
import android.widget.ImageView
import androidx.core.content.ContextCompat
import coil3.ImageLoader
import coil3.asDrawable
import coil3.imageLoader
import coil3.request.ImageRequest
import coil3.target.ImageViewTarget
import com.androlua.LuaContext
import org.luaj.LuaError
import org.luaj.LuaValue
import java.io.File

/**
 * loadlayout `src`：R.drawable 同步；工程位图 / 路径 / URL Coil 异步；`.lua` 同步。
 * 解析顺序对齐 [org.luaj.android.res]。
 */
internal class LayoutSrcLoader(
    private val context: Context,
    private val luaContext: LuaContext,
) {
    private val imageLoader: ImageLoader = context.imageLoader
    private val fileCache = HashMap<String, Any>(16)

    fun apply(rawValue: LuaValue, hostView: View, viewLua: LuaValue) {
        when {
            rawValue.isuserdata(Bitmap::class.java) ->
                viewLua.jset("ImageBitmap", rawValue.touserdata(Bitmap::class.java))
            rawValue.isuserdata(Drawable::class.java) -> {
                val d = rawValue.touserdata(Drawable::class.java) as Drawable
                // ImageView 直接 set，避免 jset 属性名/setter 解析偶发丢图
                if (hostView is ImageView) hostView.setImageDrawable(d)
                else viewLua.jset("ImageDrawable", d)
            }
            rawValue.isstring() || rawValue.isnumber() -> {
                val raw = rawValue.tojstring()?.trim().orEmpty()
                if (raw.isEmpty()) return
                if (isDrawableResourceRef(raw)) applyDrawableRef(raw, hostView, viewLua)
                else enqueue(raw, hostView, viewLua)
            }
            else -> throw LuaError(
                "src 需要 Bitmap / Drawable / 路径 / URL / @drawable/name，实际为 ${rawValue.typename()}"
            )
        }
    }

    private fun isDrawableResourceRef(raw: String): Boolean =
        raw.startsWith("@drawable/") ||
            raw.startsWith("@android:drawable/") ||
            raw.startsWith("drawable/")

    private fun resourceName(raw: String): Pair<String, Boolean> = when {
        raw.startsWith("@android:drawable/") ->
            raw.removePrefix("@android:drawable/") to true
        raw.startsWith("@drawable/") ->
            raw.removePrefix("@drawable/") to false
        raw.startsWith("drawable/") ->
            raw.removePrefix("drawable/") to false
        else -> raw to false
    }

    private fun applyDrawableRef(raw: String, hostView: View, viewLua: LuaValue) {
        resolveAndroidRes(raw)?.let {
            applyDrawable(hostView, viewLua, it)
            return
        }
        val (name, isAndroid) = resourceName(raw)
        if (isAndroid || name.isBlank()) {
            throw LuaError("src 未找到 android drawable「$raw」")
        }
        findProjectFile(name)?.let {
            enqueue(it, hostView, viewLua)
            return
        }
        loadProjectLua(name)?.let {
            applyDrawable(hostView, viewLua, it)
            return
        }
        throw LuaError(
            "src 未找到 drawable「$raw」" +
                "（已查 R.drawable / 工程 res/drawable 位图与 .lua）"
        )
    }

    private fun resolveAndroidRes(raw: String): Drawable? {
        val (name, isAndroid) = resourceName(raw)
        if (name.isBlank()) return null
        if (isAndroid) {
            val id = context.resources.getIdentifier(name, "drawable", "android")
            if (id != 0) return ContextCompat.getDrawable(context, id)?.mutate()
            return null
        }
        val pkg = context.packageName
        for (n in arrayOf(name, "ic_$name")) {
            val id = context.resources.getIdentifier(n, "drawable", pkg)
            if (id != 0) return ContextCompat.getDrawable(context, id)?.mutate()
        }
        return null
    }

    private fun projectBase(name: String): String? = try {
        luaContext.getLuaPath("res/drawable", name)
    } catch (_: Exception) {
        null
    }

    private fun findProjectFile(name: String): File? {
        val cached = fileCache[name]
        if (cached === MISS) return null
        if (cached is File) return cached
        val base = projectBase(name) ?: run {
            fileCache[name] = MISS
            return null
        }
        for (ext in org.luaj.android.res.imageExtensions) {
            val f = File("$base.$ext")
            if (f.isFile) {
                fileCache[name] = f
                return f
            }
        }
        fileCache[name] = MISS
        return null
    }

    private fun loadProjectLua(name: String): Drawable? {
        val base = projectBase(name) ?: return null
        val luaFile = File("$base.lua")
        if (!luaFile.isFile) return null
        val globals = luaContext.luaState
        val v = runCatching {
            globals.loadfile(luaFile.absolutePath, globals).call()
        }.getOrNull() ?: return null
        return when {
            v.isnil() -> null
            v.isuserdata(Drawable::class.java) ->
                v.touserdata(Drawable::class.java) as Drawable
            v.isuserdata(Bitmap::class.java) ->
                BitmapDrawable(
                    context.resources,
                    v.touserdata(Bitmap::class.java) as Bitmap
                )
            else -> null
        }
    }

    private fun enqueue(data: Any, hostView: View, viewLua: LuaValue) {
        if (hostView is ImageView) {
            imageLoader.enqueue(
                ImageRequest.Builder(context)
                    .data(data)
                    .target(ImageViewTarget(hostView))
                    .build()
            )
            return
        }
        imageLoader.enqueue(
            ImageRequest.Builder(context)
                .data(data)
                .target { image ->
                    val d = image.asDrawable(context.resources)
                    val apply = Runnable { viewLua.jset("ImageDrawable", d) }
                    if (hostView.isAttachedToWindow) apply.run()
                    else hostView.post(apply)
                }
                .build()
        )
    }

    private fun applyDrawable(hostView: View, viewLua: LuaValue, d: Drawable) {
        if (hostView is ImageView) hostView.setImageDrawable(d)
        else viewLua.jset("ImageDrawable", d)
    }

    companion object {
        private val MISS = Any()
    }
}

---@diagnostic disable: undefined-global
import "java.io.File"
import "com.androlua.LuaTarget"
import "androidx.core.view.GravityCompat"
import "android.view.LayoutInflater"

local ColorUtil = this.themeUtil
-- Anime
local AnimatorSet = bindClass "android.animation.AnimatorSet"
local ObjectAnimator = bindClass "android.animation.ObjectAnimator"
local DecelerateInterpolator = luajava.newInstance "android.view.animation.DecelerateInterpolator"

-- RecyclerView
import "androidx.recyclerview.widget.RecyclerView"
import "androidx.recyclerview.widget.LinearLayoutManager"
-- RecyclerAdapter
import "github.znzsofficial.adapter.PopupRecyclerAdapter"
import "github.znzsofficial.adapter.LuaCustRecyclerHolder"
import "com.nekolaska.internal.FileItemHolder"

import "android.util.TypedValue"

local ImageRequestBuilder = bindClass "coil3.request.ImageRequest$Builder"

import "mods.utils.EditorUtil"
import "mods.utils.ActivityUtil"

local Bean_Path
local res = res
local table = table
local utf8 = utf8
local string = string
local rawget = rawget
local R = R

local _M = {}
local FileList
local Anim

-- 扩展名 → 图标名
local suffix_image = setmetatable({
    lua = "file_code",
    luac = "file_c_code",
    java = "file_code",
    kt = "file_code",
    xml = "file_xml",
    apk = "file_apk",
    aab = "file_apk",
    class = "file_java",
    jar = "file_java",
    dex = "file_dex",
    alp = "file_zip",
    zip = "file_zip",
    bak = "file_zip",
    yml = "file_json",
    yaml = "file_json",
    json = "file_json",
    txt = "file_text",
    flac = "file_audio",
    mp3 = "file_audio",
    wav = "file_audio",
    ogg = "file_audio",
    mp4 = "file_video",
    m3u8 = "file_video",
    avi = "file_video",
    mkv = "file_video",
    idsig = "file_sig",
    png = "file_img",
    jpg = "file_img",
    jpeg = "file_img",
    gif = "file_img",
    bmp = "file_img",
    svg = "file_img",
    webp = "file_img",
    heif = "file_img",
    heic = "file_img",
    avif = "file_img",
    md = "file_text",
    log = "file_text",
    properties = "file_text",
    gradle = "file_code",
    kts = "file_code",
    toml = "file_json",
    cfg = "file_json",
    ini = "file_json",
    sh = "file_code",
    bat = "file_code",
    html = "file_code",
    css = "file_code",
    js = "file_code",
}, {
    __index = function(self, key)
        return rawget(self, key) or "file"
    end
})

-- 图标名 → 打开方式
-- "editor"=编辑器打开, "image"=图片查看, "dex"=dex工具, "install"=安装, "external"=系统打开
local openAction = {
    file_code   = "editor",
    file_xml    = "editor",
    file_json   = "editor",
    file_text   = "editor",
    file_img    = "image",
    file_dex    = "dex",
    file_java   = "external",
    file_apk    = "install",
    file_zip    = "external",
    file_sig    = "external",
    file_audio  = "external",
    file_video  = "external",
    file_c_code = "external",
    file        = "external",
}

_M.init = function()
    Bean_Path = Bean.Path

    Anim = AnimatorSet()
    local X = ObjectAnimator.ofFloat(mRecycler, "translationY", { 50, 0 })
    local A = ObjectAnimator.ofFloat(mRecycler, "alpha", { 0, 1 })
    Anim.play(A).with(X)
    Anim.setDuration(400)
        .setInterpolator(DecelerateInterpolator)

    luajava.newInstance("me.zhanghai.android.fastscroll.FastScrollerBuilder", mRecycler)
           .useMd2Style()
           .setPadding(0, this.dpToPx(8), this.dpToPx(2), this.dpToPx(8))
           .build()

    local res_drawable = res.drawable

    local imageLoader = this.getImageLoader()
    local error_project = res_drawable("android_studio", ColorUtil.getColorSecondary())

    local size = this.dpToPx(28)
    error_project.setBounds(0, 0, size, size)
    -- 清空文件列表
    FileList = {}

    -- 实例化 LayoutManager
    local layoutManager = LinearLayoutManager(
            activity,
            RecyclerView.VERTICAL,
            false)

    local inflater = LayoutInflater.from(this)
    local itemRes = R.layout.item_file
    -- 实例化 PopupRecyclerAdapter
    adapter_rv = PopupRecyclerAdapter(
            activity,
            PopupRecyclerAdapter.PopupCreator({
                getItemCount = function()
                    return #FileList
                end,
                getItemViewType = function()
                    return 0
                end,
                getPopupText = function(_, position)
                    return utf8.sub(FileList[position + 1].file_name, 1, 1)
                end,
                onCreateViewHolder = function(parent, viewType)
                    local view = inflater.inflate(itemRes, parent, false)
                    return FileItemHolder(view)
                end,
                onViewRecycled = function(holder)
                    holder.unbind()
                end,
                onBindViewHolder = function(holder, position)
                    local view = holder.bind()
                    local v = FileList[position + 1]
                    local v_path = v.path

                    view.name.setText(v.file_name)
                    -- 重置图标，防止 ViewHolder 复用时显示旧的异步加载结果
                    view.name.setCompoundDrawables(nil, nil, nil, nil)

                    if v.img == "Project" then
                        imageLoader.enqueue(
                                ImageRequestBuilder(activity)
                                             .data(v_path .. "/icon.png")
                                             .target(LuaTarget(this, LuaTarget.Listener {
                                    onError = function()
                                        pcall(function()
                                            view.name.setCompoundDrawables(error_project, nil, nil, nil)
                                        end)
                                    end,
                                    onSuccess = function(drawable)
                                        pcall(function()
                                            drawable.setBounds(0, 0, size, size)
                                            view.name.setCompoundDrawables(drawable, nil, nil, nil)
                                        end)
                                    end
                                }))          .build()
                        )
                    elseif (v.isDirectory and (v.file_name == "mods" or v.file_name == "libs")) then
                        pcall(function()
                            local drawable = res_drawable["folder_mod"]
                            drawable.setBounds(0, 0, size, size)
                            view.name.setCompoundDrawables(drawable, nil, nil, nil)
                        end)
                    else
                        pcall(function()
                            local iconName = v.img == "file_dex" and "file_java" or v.img
                            local drawable = res_drawable[iconName]
                            drawable.setBounds(0, 0, size, size)
                            view.name.setCompoundDrawables(drawable, nil, nil, nil)
                        end)
                    end

                    view.contents.onLongClick = function()
                        if v.img == "folder_up" then
                            return
                        elseif v.isDirectory then
                            MainActivity.Public.dirMenu(v_path, v.file_name)
                        else
                            MainActivity.Public.fileMenu(v_path, v.file_name)
                        end
                        return true
                    end

                    view.contents.onClick = function()

                        if not File(v_path).canRead() then
                            MainActivity.Public.snack(res.string.NoReadPms)
                            return
                        end

                        if v.isDirectory then
                            PathManager.updateDir(v_path)
                            filetab.setPath(v_path)
                            _M.update()
                            return
                        end

                        local action = openAction[v.img] or "external"

                        if action == "editor" then
                            EditorUtil.fromRecy = true
                            EditorUtil.load(v_path)
                            drawer.closeDrawer(GravityCompat.START)
                        elseif action == "image" then
                            ActivityUtil.new("photo", v_path)
                        elseif action == "dex" then
                            MainActivity.Public.dexDialog(v_path)
                        elseif action == "install" then
                            MainActivity.Public.InstallApk(v_path)
                        else -- "external"
                            this.openFile(v_path, function()
                                MainActivity.Public.snack(res.string.NoSupport)
                            end)
                        end

                    end

                end,
            }))
    mRecycler.setAdapter(adapter_rv).setLayoutManager(layoutManager)

    filetab.addFileTabListener {
      onSelected = function(path)
        -- 将 /sdcard 映射回实际存储根路径
        local realPath = path:gsub("/sdcard", Bean_Path.system_root)
        local dir = File(realPath)

        if not dir.exists() or not dir.isDirectory() then
          -- 路径不存在或不是目录，回退到当前有效目录
          filetab.setDirectPath(Bean_Path.this_dir)
          MainActivity.Public.snack(res.string.NoReadPms)
          return
        end

        if not dir.canRead() then
          -- 无读取权限，回退
          filetab.setDirectPath(Bean_Path.this_dir)
          MainActivity.Public.snack(res.string.NoReadPms)
          return
        end

        PathManager.updateDir(realPath)
        _M.update()
      end
    }
    return _M
end

-- 排序函数提到模块级，避免每次 getList 都创建闭包
local sortByName = function(a, b)
    return a.file_name < b.file_name
end

local getList = function()
    local path = Bean_Path.this_dir
    local table_sort = table.sort
    local match = string.match

    local dir = File(path)
    if not dir.canRead() then
        return
    end

    -- 使用 listFiles() 直接获取 File[]，避免对每个文件名重新构造 File 对象
    local files = dir.listFiles()
    if not files then
        return
    end

    local dirs = {}
    local regulars = {}
    local dirCount = 0
    local fileCount = 0

    for _, f in (files) do
        local name = tostring(f.getName())
        -- 过滤隐藏文件（以 . 开头），但保留 .gitignore 等常见配置文件
        if name:sub(1, 1) ~= "." then
            local fullPath = tostring(f.getPath())
            if f.isDirectory() then
                dirCount = dirCount + 1
                dirs[dirCount] = {
                    path = fullPath,
                    file_name = name,
                    isDirectory = true,
                }
            else
                fileCount = fileCount + 1
                regulars[fileCount] = {
                    path = fullPath,
                    file_name = name,
                    isDirectory = false,
                }
            end
        end
    end

    table_sort(dirs, sortByName)
    table_sort(regulars, sortByName)

    -- 判断当前目录状态
    local isRoot = (path == Bean_Path.system_root)
    local isProjectDir = (path == Bean_Path.app_root_pro_dir)

    -- 直接构建最终 FileList，不再二次复制
    local list = {}
    local idx = 0

    -- 非根目录时插入返回上级项
    if not isRoot then
        idx = 1
        list[1] = {
            isDirectory = true,
            file_name = "...",
            path = dir.getParent(),
            img = "folder_up",
        }
    end

    -- 目录优先
    for i = 1, dirCount do
        idx = idx + 1
        local d = dirs[i]
        d.img = isProjectDir and "Project" or "folder"
        list[idx] = d
    end

    -- 然后是文件
    for i = 1, fileCount do
        idx = idx + 1
        local f = regulars[i]
        local ext = match(f.path, "%.([^%.]+)$")
        f.img = suffix_image[ext]
        list[idx] = f
    end

    FileList = list
end

local updateCallback = function()
    adapter_rv.notifyDataSetChanged()
    Anim.start()
    swipeRefresh.setRefreshing(false)
end

_M.update = function()
    xTask(getList, updateCallback)
    return _M
end

_M.delete = function(path)
    for k, v in ipairs(FileList) do
        if v.path == path then
            table.remove(FileList, k)
            return k
        end
    end
    return nil
end

return _M
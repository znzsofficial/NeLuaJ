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
import "mods.utils.TabUtil"
import "com.google.android.material.dialog.MaterialAlertDialogBuilder"
import "com.androlua.LuaUtil"

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
local selectMode = false
local selected = {} -- path -> true
-- clipboard: { mode = "copy"|"cut", paths = {..} }
local fileClipboard = nil

-- 扩展名 → 图标名
local suffix_image = setmetatable({
    lua = "file_code",
    luac = "file_c_code",
    java = "file_java",
    kt = "file_code",
    kts = "file_code",
    xml = "file_xml",
    apk = "file_apk",
    aab = "file_apk",
    class = "file_java",
    jar = "file_java",
    jad = "file_java",
    smali = "file_java",
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

-- 文件夹名（小写）→ 图标类型
local folder_icon_by_name = {
    mods = "folder_mod",
    mod = "folder_mod",
    modules = "folder_mod",
    ["module"] = "folder_mod", -- module 在 LuaJ 中不可作裸标识符
    plugins = "folder_mod",
    plugin = "folder_mod",
    extensions = "folder_mod",
    extension = "folder_mod",
    libs = "folder_lib",
    lib = "folder_lib",
    library = "folder_lib",
    libraries = "folder_lib",
    dependencies = "folder_lib",
    vendor = "folder_lib",
    node_modules = "folder_lib",
    src = "folder_src",
    source = "folder_src",
    sources = "folder_src",
    java = "folder_java",
    kotlin = "folder_java",
    kotlin_src = "folder_java",
    main = "folder_src",
    res = "folder_res",
    resources = "folder_res",
    resource = "folder_res",
    drawable = "folder_res",
    mipmap = "folder_res",
    layout = "folder_res",
    values = "folder_res",
    raw = "folder_res",
    assets = "folder_assets",
    asset = "folder_assets",
    ["static"] = "folder_assets",
    ["public"] = "folder_assets",
    build = "folder_build",
    builds = "folder_build",
    out = "folder_build",
    output = "folder_build",
    outputs = "folder_build",
    bin = "folder_build",
    dist = "folder_build",
    target = "folder_build",
    release = "folder_build",
    debug = "folder_build",
    intermediate = "folder_build",
    intermediates = "folder_build",
    [".git"] = "folder_git",
    git = "folder_git",
    github = "folder_git",
    gitlab = "folder_git",
    vcs = "folder_git",
    test = "folder_test",
    tests = "folder_test",
    testing = "folder_test",
    androidtest = "folder_test",
    unittest = "folder_test",
    spec = "folder_test",
    specs = "folder_test",
    doc = "folder_doc",
    docs = "folder_doc",
    documentation = "folder_doc",
    javadoc = "folder_doc",
    help = "folder_doc",
    wiki = "folder_doc",
    config = "folder_config",
    configs = "folder_config",
    configuration = "folder_config",
    conf = "folder_config",
    settings = "folder_config",
    gradle = "folder_config",
    meta_inf = "folder_config",
    ["meta-inf"] = "folder_config",
    properties = "folder_config",
    [".gradle"] = "folder_config",
    [".idea"] = "folder_config",
    [".vscode"] = "folder_config",
    [".github"] = "folder_git",
}

local function resolveFolderIcon(name, isProjectRootListing)
    if isProjectRootListing then
        return "Project"
    end
    if not name or name == "" then
        return "folder"
    end
    local key = string.lower(name)
    local mapped = folder_icon_by_name[key]
    if mapped then return mapped end
    -- 常见后缀 / 模糊匹配
    if key:find("test", 1, true) then return "folder_test" end
    if key:find("build", 1, true) or key:find("output", 1, true) then return "folder_build" end
    if key:sub(1, 1) == "." then return "folder_hidden" end
    return "folder"
end

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
    local size = this.dpToPx(28)

    -- 主题色：矢量图标按类型 tint（不再依赖 PNG 写死颜色）
    local cPrimary = ColorUtil.getColorPrimary()
    local cSecondary = ColorUtil.getColorSecondary()
    local cOnSurface = ColorUtil.getColorOnSurface()
    local cOnSurfaceVar = ColorUtil.getColorOnSurfaceVariant()
    local cTertiary = ColorUtil.getColorTertiary()
    local cPrimaryContainer = ColorUtil.getColorPrimaryContainer()
    local cSurface = ColorUtil.getColorSurface()

    local iconColor = {
        folder = cPrimary,
        folder_up = cOnSurfaceVar,
        folder_mod = cSecondary,
        folder_lib = cSecondary,
        folder_src = cPrimary,
        folder_res = cTertiary,
        folder_assets = cTertiary,
        folder_build = 0xFFFF9800,
        folder_git = 0xFFE91E63,
        folder_test = 0xFF4CAF50,
        folder_doc = cOnSurfaceVar,
        folder_config = cOnSurfaceVar,
        folder_java = 0xFFFF9800,
        folder_hidden = cOnSurfaceVar,
        Project = cSecondary,
        android_studio = cSecondary,
        file_code = cPrimary,
        file_c_code = cSecondary,
        file_xml = cTertiary,
        file_json = 0xFFF9A825,
        file_text = cOnSurfaceVar,
        file_img = 0xFF4CAF50,
        file_audio = 0xFF9C27B0,
        file_video = 0xFFE91E63,
        file_zip = cOnSurfaceVar,
        file_apk = 0xFF8BC34A,
        file_java = 0xFFFF9800,
        file_dex = 0xFFFF5722,
        file_sig = cOnSurfaceVar,
        file = cOnSurfaceVar,
    }
    setmetatable(iconColor, {
        __index = function() return cOnSurfaceVar end
    })

    local function iconOf(name, color)
        local d = res_drawable(name, color or iconColor[name])
        if d then
            d.setBounds(0, 0, size, size)
        end
        return d
    end

    local function isUpItem(v)
        return v.is_up or v.file_name == "..." or v.img == "folder_up"
    end

    local error_project = iconOf("android_studio", cSecondary)

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
                    local t = holder.Tag
                    if t and t.coil_disposable then
                        t.coil_disposable.dispose()
                        t.coil_disposable = nil
                    end
                    holder.unbind()
                end,
                onBindViewHolder = function(holder, position)
                    local view = holder.bind()
                    local v = FileList[position + 1]
                    local v_path = v.path
                    local bind_token = v_path .. "\0" .. tostring(v.img) .. "\0" .. tostring(v.file_name)
                    local tag = holder.Tag

                    -- 取消上一绑定时的 Coil 请求，避免异步回调写到复用后的 item
                    if tag and tag.coil_disposable then
                        tag.coil_disposable.dispose()
                        tag.coil_disposable = nil
                    end
                    if tag then tag.bind_token = bind_token end

                    local isUp = isUpItem(v)
                    local isChecked = false
                    if selectMode and selected[v_path] then
                        isChecked = true
                    end
                    view.name.setText(tostring(v.file_name or ""))
                    view.name.setCompoundDrawables(nil, nil, nil, nil)

                    if selectMode and not isUp then
                        view.check.setVisibility(0)
                        view.check.setChecked(isChecked)
                    else
                        view.check.setVisibility(8)
                        view.check.setChecked(false)
                    end
                    view.contents.setChecked(isChecked)
                    if isChecked then
                        view.contents.setStrokeWidth(this.dpToPx(1.5))
                        view.contents.setStrokeColor(cPrimary)
                        view.contents.setCardBackgroundColor(cPrimaryContainer)
                    else
                        view.contents.setStrokeWidth(0)
                        view.contents.setStrokeColor(0)
                        view.contents.setCardBackgroundColor(cSurface)
                    end

                    local function setIcon(drawable)
                        if drawable then
                            view.name.setCompoundDrawables(drawable, nil, nil, nil)
                        end
                    end

                    if isUp then
                        setIcon(iconOf("folder_up"))
                    elseif v.img == "Project" then
                        setIcon(error_project)
                        local disposable = imageLoader.enqueue(
                            ImageRequestBuilder(activity)
                                .data(v_path .. "/icon.png")
                                .target(LuaTarget(this, LuaTarget.Listener {
                                    onError = function()
                                        if not tag or tag.bind_token ~= bind_token then return end
                                        setIcon(error_project)
                                    end,
                                    onSuccess = function(drawable)
                                        if not tag or tag.bind_token ~= bind_token then return end
                                        drawable.setBounds(0, 0, size, size)
                                        setIcon(drawable)
                                    end
                                })).build()
                        )
                        if tag then
                            tag.coil_disposable = disposable
                        end
                    else
                        setIcon(iconOf(v.img))
                    end

                    view.contents.onLongClick = function()
                        if isUpItem(v) then
                            return true
                        end
                        if selectMode then
                            if selected[v_path] then
                                selected[v_path] = nil
                            else
                                selected[v_path] = true
                            end
                            _M.refreshSelectUi()
                            return true
                        end
                        if v.isDirectory then
                            MainActivity.Public.dirMenu(v_path, v.file_name)
                        else
                            MainActivity.Public.fileMenu(v_path, v.file_name)
                        end
                        return true
                    end

                    view.contents.onClick = function()
                        if selectMode then
                            if isUpItem(v) then return end
                            if selected[v_path] then
                                selected[v_path] = nil
                            else
                                selected[v_path] = true
                            end
                            _M.refreshSelectUi()
                            return
                        end

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

                        local action = openAction[v.img]
                        if not action then
                            action = "external"
                        end

                        if action == "editor" then
                            EditorUtil.fromRecy = true
                            EditorUtil.load(v_path)
                            local Init = require "activities.main.Init"
                            if not Init.isTabletMode() then
                                drawer.closeDrawer(GravityCompat.START)
                            end
                        elseif action == "image" then
                            ActivityUtil.open("photo", v_path)
                        elseif action == "dex" then
                            MainActivity.Public.dexDialog(v_path)
                        elseif action == "install" then
                            MainActivity.Public.InstallApk(v_path)
                        else
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
    local path = tostring(Bean_Path.this_dir)
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

    -- 非根目录时插入返回上级项（固定 folder_up，不受 isProjectDir 影响）
    if not isRoot then
        idx = 1
        list[1] = {
            isDirectory = true,
            file_name = "...",
            path = dir.getParent(),
            img = "folder_up",
            is_up = true,
        }
    end

    -- 目录优先（按名称映射更多文件夹类型）
    for i = 1, dirCount do
        idx = idx + 1
        local d = dirs[i]
        -- 工程根列表里工程文件夹用 Project；「...」已单独插入，不会进这里
        d.img = resolveFolderIcon(d.file_name, isProjectDir)
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

local function selectablePaths()
    local list = {}
    if not FileList then return list end
    for _, v in ipairs(FileList) do
        if not v.is_up and v.file_name ~= "..." then
            list[#list + 1] = v.path
        end
    end
    return list
end

local function selectedList()
    local list = {}
    for _, path in ipairs(selectablePaths()) do
        if selected[path] then list[#list + 1] = path end
    end
    return list
end

local function selectedCount()
    return #selectedList()
end

-- 切目录后丢掉不在当前列表的勾选，避免「已选 N」虚高
local function pruneSelected()
    if not FileList then
        selected = {}
        return
    end
    local keep = {}
    for _, v in ipairs(FileList) do
        if selected[v.path] and not v.is_up and v.file_name ~= "..." then
            keep[v.path] = true
        end
    end
    selected = keep
end

local updateCallback = function()
    pruneSelected()
    if adapter_rv then adapter_rv.notifyDataSetChanged() end
    Anim.start()
    swipeRefresh.setRefreshing(false)
    _M.refreshSelectUi()
end

_M.update = function()
    if not Bean_Path then return _M end
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

_M.isSelectMode = function()
    return selectMode
end

_M.refreshSelectUi = function()
    if adapter_rv then adapter_rv.notifyDataSetChanged() end
    if selectMode then
        fileNormalBar.setVisibility(8)
        fileSelectBar.setVisibility(0)
    else
        fileNormalBar.setVisibility(0)
        fileSelectBar.setVisibility(8)
        btnFileSelect.setText(res.string.media_select)
    end
    local hasClip = false
    if fileClipboard and fileClipboard.paths and #fileClipboard.paths > 0 then
        hasClip = true
    end
    if hasClip then
        btnFilePaste.setVisibility(0)
    else
        btnFilePaste.setVisibility(8)
    end
    -- 仅工程列表根（Projects）显示「创建工程」
    local atProjectsRoot = Bean_Path
        and Bean_Path.this_dir == Bean_Path.app_root_pro_dir
    if btnFileNewProject then
        btnFileNewProject.setVisibility(atProjectsRoot and 0 or 8)
    end
end

_M.setSelectMode = function(on, seedPath)
    if on then
        selectMode = true
        if seedPath and seedPath ~= "" then
            selected[seedPath] = true
        end
    else
        selectMode = false
        selected = {}
    end
    _M.refreshSelectUi()
end

_M.enterSelect = function(seedPath)
    _M.setSelectMode(true, seedPath)
end

_M.toggleSelectMode = function()
    if selectMode then
        _M.setSelectMode(false)
    else
        _M.setSelectMode(true)
    end
end

_M.selectAll = function()
    if not selectMode then return end
    local allOn = true
    for _, path in ipairs(selectablePaths()) do
        if not selected[path] then
            allOn = false
            break
        end
    end
    for _, path in ipairs(selectablePaths()) do
        if allOn then
            selected[path] = nil
        else
            selected[path] = true
        end
    end
    _M.refreshSelectUi()
end

local function setClipboard(mode, paths)
    if not paths or #paths == 0 then
        MainActivity.Public.snack(res.string.media_none_selected)
        return
    end
    fileClipboard = { mode = mode, paths = paths }
    if mode == "cut" then
        MainActivity.Public.snack(string.format(res.string.file_cut_ok, #paths))
    else
        MainActivity.Public.snack(string.format(res.string.file_copy_ok, #paths))
    end
    if selectMode then
        _M.setSelectMode(false)
    else
        _M.refreshSelectUi()
    end
end

_M.copySelected = function()
    setClipboard("copy", selectedList())
end

_M.cutSelected = function()
    setClipboard("cut", selectedList())
end

_M.copyPaths = function(paths)
    setClipboard("copy", paths)
end

_M.cutPaths = function(paths)
    setClipboard("cut", paths)
end

local function uniqueDest(dir, name)
    local dest = dir .. "/" .. name
    if not File(dest).exists() then return dest end
    local base, ext = name:match("^(.*)(%.[^%.]+)$")
    if not base then base, ext = name, "" end
    local i = 1
    while true do
        local cand = string.format("%s/%s (%d)%s", dir, base, i, ext)
        if not File(cand).exists() then return cand end
        i = i + 1
        if i > 99 then return cand end
    end
end

_M.pasteClipboard = function()
    if not fileClipboard or not fileClipboard.paths or #fileClipboard.paths == 0 then
        MainActivity.Public.snack(res.string.file_clipboard_empty)
        return
    end
    local destDir = Bean_Path.this_dir
    local mode = fileClipboard.mode
    local okN, failN = 0, 0
    for _, src in ipairs(fileClipboard.paths) do
        local name = File(src).getName()
        local dest = uniqueDest(destDir, tostring(name))
        if mode == "cut" and (destDir == src or destDir:find(src .. "/", 1, true) == 1) then
            failN = failN + 1
        else
            if File(src).isDirectory() then
                LuaUtil.copyDir(File(src), File(dest))
            else
                LuaUtil.copyFile(src, dest)
            end
            if mode == "cut" then
                TabUtil.removeUnder(src)
                LuaUtil.rmDir(File(src))
            end
            okN = okN + 1
        end
    end
    if mode == "cut" then
        fileClipboard = nil
        TabUtil.checkAll()
    end
    _M.setSelectMode(false)
    _M.update()
    MainActivity.Public.snack(string.format(res.string.file_paste_ok, okN, failN))
end

_M.deleteSelected = function()
    local paths = selectedList()
    if #paths == 0 then
        MainActivity.Public.snack(res.string.media_none_selected)
        return
    end
    MaterialAlertDialogBuilder(activity)
        .setTitle(res.string.delete)
        .setMessage(string.format(res.string.media_delete_n, #paths))
        .setPositiveButton(android.R.string.ok, function()
            for _, path in ipairs(paths) do
                -- 目录/工程：关掉其下所有已开标签，不仅精确路径
                TabUtil.removeUnder(path)
                LuaUtil.rmDir(File(path))
            end
            TabUtil.checkAll()
            _M.setSelectMode(false)
            _M.update()
            MainActivity.Public.snack(string.format(res.string.media_deleted_n, #paths))
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .show()
end

_M.goProjectHome = function()
    local root = Bean_Path.app_root_pro_dir
    if Bean.Project and Bean.Project.this_project and Bean.Project.this_project ~= "" then
        local projectRoot = Bean_Path.app_root_pro_dir .. "/" .. Bean.Project.this_project
        if File(projectRoot).isDirectory() then
            root = projectRoot
        end
    end
    _M.setSelectMode(false)
    PathManager.updateDir(root)
    filetab.setPath(root)
    _M.update()
    MainActivity.Public.snack(res.string.file_at_project)
end

local function promptCreate(isDir)
    local sublayout = {}
    local title
    if isDir then
        title = res.string.new_dir
    else
        title = res.string.new_file
    end
    MaterialAlertDialogBuilder(activity)
        .setTitle(title)
        .setView(loadlayout(res.layout.dialog_fileinput, sublayout))
        .setPositiveButton(android.R.string.ok, function()
            local name = tostring(sublayout.file_name.getText())
            if name == "" then return end
            local new_path = Bean_Path.this_dir .. "/" .. name
            if File(new_path).exists() then
                MainActivity.Public.snack(res.string.have_same_name)
                return
            end
            if isDir then
                MainActivity.Public.newDir(new_path)
            else
                swipeRefresh.setRefreshing(true)
                LuaFileUtil.create(new_path, "")
                _M.update()
            end
            MainActivity.Public.snack(res.string.create_success)
        end)
        .setNegativeButton(android.R.string.cancel, nil)
        .show()
    if isDir then
        sublayout.file_name.setHint(res.string.new_dir)
    else
        sublayout.file_name.setHint(res.string.new_file)
    end
end

-- 顶栏长按：handler 可自定义；默认 snack 说明文案
local function bindLong(view, handler)
    view.setLongClickable(true)
    view.onLongClick = function()
        handler()
        return true
    end
end

local function tipLong(view, text)
    bindLong(view, function()
        MainActivity.Public.snack(text)
    end)
end

_M.bindChrome = function()
    btnFileHome.onClick = function()
        _M.goProjectHome()
    end
    tipLong(btnFileHome, res.string.file_at_project)

    btnFileNewFile.onClick = function()
        promptCreate(false)
    end
    -- 长按新建文件 → 新建文件夹
    bindLong(btnFileNewFile, function()
        promptCreate(true)
    end)

    btnFileNewDir.onClick = function()
        promptCreate(true)
    end
    -- 长按新建文件夹 → 新建文件
    bindLong(btnFileNewDir, function()
        promptCreate(false)
    end)

    btnFileNewProject.onClick = function()
        require("activities.main.Actions").createProject()
    end
    tipLong(btnFileNewProject, res.string.create_project)

    btnFileSelect.onClick = function()
        _M.toggleSelectMode()
    end
    tipLong(btnFileSelect, res.string.media_select)

    btnFileSelectAll.onClick = function()
        _M.selectAll()
    end
    tipLong(btnFileSelectAll, res.string.media_select_all)

    btnFileCopy.onClick = function()
        _M.copySelected()
    end
    tipLong(btnFileCopy, res.string.copy)

    btnFileCut.onClick = function()
        _M.cutSelected()
    end
    tipLong(btnFileCut, res.string.file_cut)

    btnFilePaste.onClick = function()
        _M.pasteClipboard()
    end
    bindLong(btnFilePaste, function()
        if not fileClipboard or not fileClipboard.paths or #fileClipboard.paths == 0 then
            MainActivity.Public.snack(res.string.file_clipboard_empty)
            return
        end
        local n = #fileClipboard.paths
        local mode = res.string.copy
        if fileClipboard.mode == "cut" then mode = res.string.file_cut end
        MainActivity.Public.snack(string.format("%s · %d", mode, n))
    end)

    btnFileDeleteSel.onClick = function()
        _M.deleteSelected()
    end
    tipLong(btnFileDeleteSel, res.string.delete)

    btnFileCancelSel.onClick = function()
        _M.setSelectMode(false)
    end
    tipLong(btnFileCancelSel, res.string.media_cancel_select)

    _M.refreshSelectUi()
    return _M
end

return _M
import "java.io.File"
import "java.lang.Runtime"
import "com.androlua.LuaTarget"
import "androidx.core.view.GravityCompat"
import "android.view.LayoutInflater"

local ColorUtil = this.globalData.ColorUtil
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

local Executors = bindClass "java.util.concurrent.Executors"
local Handler = bindClass "android.os.Handler"
local Looper = bindClass "android.os.Looper"
local mainLooper = Looper.getMainLooper()
local handler = Handler(mainLooper)
local executor = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())

local Bean_Path
local res = res
local table = table
local utf8 = utf8
local rawget = rawget
local R = R

local _M = {}
local FileList
local Anim

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
    dex = "file_java",
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
    mp4 = "file_video",
    m3u8 = "file_video",
    avi = "file_video",
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
    avif = "file_img"
}, {
    __index = function(self, key)
        return rawget(self, key) or "file"
    end
})

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
    local error_project = this.getResDrawable("android_studio", ColorUtil.getColorSecondary())

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
                    local view = inflater.inflate(R.layout.item_file, parent, false)
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
                        local drawable = res_drawable["folder_mod"]
                        drawable.setBounds(0, 0, size, size)
                        view.name.setCompoundDrawables(drawable, nil, nil, nil)
                    else
                        local drawable = res_drawable[v.img]
                        drawable.setBounds(0, 0, size, size)
                        view.name.setCompoundDrawables(drawable, nil, nil, nil)
                    end

                    view.contents.onLongClick = function()
                        if v.img == "folder_up" then
                            return
                        elseif v.isDirectory then
                            MainActivity.Public.dirMenu(v_path, v.file_name, position)
                        else
                            MainActivity.Public.fileMenu(v_path, v.file_name, position)
                        end
                        return true
                    end

                    view.contents.onClick = function()

                        if not File(v_path).canRead() then
                            MainActivity.Public.snack(res.string.NoReadPms)
                            return
                        end

                        if v.isDirectory then
                            PathManager.update_this_dir(v_path)
                            filetab.setPath(Bean_Path.this_dir)
                            _M.update()
                        elseif v.img == "file_img" then
                            ActivityUtil.new("photo", v_path)
                        elseif v.img == "file_java" then
                            MainActivity.Public.dexDialog(v_path)
                        elseif v.img == "file_zip"
                                or v.img == "file_sig"
                                or v.img == "file_audio"
                                or v.img == "file_video"
                                or v.img == "file_c_code"
                                or v.img == "file" then
                            this.openFile(v_path, function()
                                MainActivity.Public.snack(res.string.NoSupport)
                            end)
                        elseif v.img == "file_apk" then
                            MainActivity.Public.InstallApk(v_path)
                        else
                            -- 来自Recycler的加载请求
                            EditorUtil.fromRecy = true
                            EditorUtil.load(v_path)
                            drawer.closeDrawer(GravityCompat.START)
                        end

                    end

                end,
            }))
    mRecycler.setAdapter(adapter_rv).setLayoutManager(layoutManager)

    --[[
    filetab.addFileTabListener{
      onSelected=function(path)
        PathManager.update_this_dir(path:gsub("/sdcard",Bean_Path.system_root))
        MainActivity.RecyclerView.update()
      end
    }]]
    return _M
end

local getList = function()
    local path = Bean_Path.this_dir
    local table_sort = table.sort

    local DirList = {}
    local _FileList = {}
    local file = File(path)
    if not file.canRead() then
        return
    end
    local fileArray = file.list()

    for _, v in (fileArray) do
        v = tostring(v)
        local full_path = path .. "/" .. v
        if File(full_path).isDirectory() then
            local k = #DirList + 1
            DirList[k] = {}
            DirList[k].path = full_path
            DirList[k].name = v
            DirList[k].isDirectory = true
        else
            local k = #_FileList + 1
            _FileList[k] = {}
            _FileList[k].path = full_path
            _FileList[k].name = v
            _FileList[k].isDirectory = false
        end
    end
    local sortFunc = function(a, b)
        return a.name < b.name
    end
    table_sort(DirList, sortFunc)
    table_sort(_FileList, sortFunc)

    for _, v in ipairs(_FileList) do
        DirList[#DirList + 1] = v
    end

    local match = string.match

    local isRoot
    local isProjectDir
    --if Bean_Path.this_dir ~= Bean_Path.legacy_system_root then
    if Bean_Path.this_dir ~= Bean_Path.system_root then
        if Bean_Path.this_dir == Bean_Path.app_root_pro_dir then
            isProjectDir = true
        end
        FileList = { { isDirectory = true, file_name = "...", path = File(Bean_Path.this_dir).getParent(), img = "folder_up" } }
    else
        isRoot = true
        FileList = {}
    end
    for k, v in ipairs(DirList) do
        local v_path = v.path
        if not isRoot then
            k = k + 1
        else
            k = k
        end
        FileList[k] = {}
        local fileInfo = FileList[k]
        fileInfo.path = v_path
        fileInfo.file_name = v.name
        fileInfo.isDirectory = v.isDirectory
        if v.isDirectory then
            fileInfo.img = isProjectDir and "Project" or "folder"
        else
            local ext = match(v_path, "%.([^%.]+)$")
            fileInfo.img = suffix_image[ext]
        end
    end

end

local updateCallback = function()
    adapter_rv.notifyDataSetChanged()
    Anim.start()
    swipeRefresh.setRefreshing(false)
end

_M.update = function()
    executor.execute(function()
        getList()
        handler.post(updateCallback)
    end)
    return _M
end

_M.delete = function(path)
    for k, v in ipairs(FileList) do
        if v["path"] == path then
            table.remove(FileList, k)
        end
    end
end

return _M
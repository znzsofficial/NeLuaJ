import "java.io.File"
import "java.lang.Runtime"
import "androidx.core.view.GravityCompat"

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

import "android.util.TypedValue"
local getDp = lambda i : TypedValue.applyDimension(1,i,activity.getResources().getDisplayMetrics())

import "coil.Coil"
import "coil.target.Target"
import "coil.request.ImageRequest"

import "mods.utils.EditorUtil"
import "mods.utils.ActivityUtil"


local Executors = bindClass"java.util.concurrent.Executors"
local Handler = bindClass"android.os.Handler"
local Looper = bindClass"android.os.Looper"
local mainLooper = Looper.getMainLooper()
local handler = Handler(mainLooper)
local executor = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())

local Bean_Path
local:res
local:table
local:utf8

local _M = {}
local FileList
local Anim


_M.suffix_image_map = {
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
  png = "file_img",
  jpg = "file_img",
  jpeg = "file_img",
  gif ="file_img",
}
local suffix_image = setmetatable({}, {
  __index = function(t, key)
    return _M.suffix_image_map[key] or "file"
  end
})

_M.init=function()
  Bean_Path = Bean.Path

  Anim = AnimatorSet()
  local X=ObjectAnimator.ofFloat(mRecycler, "translationY", {50, 0})
  local A=ObjectAnimator.ofFloat(mRecycler, "alpha", {0, 1})
  Anim.play(A).with(X)
  Anim.setDuration(400)
  .setInterpolator(DecelerateInterpolator)

  luajava.newInstance("me.zhanghai.android.fastscroll.FastScrollerBuilder", mRecycler)
  .useMd2Style()
  .setPadding(0,getDp(8),getDp(2),getDp(8))
  .build()

  local item_layout = res.layout.item_rv;
  local res_drawable= res.drawable

  local imageLoader = Coil.imageLoader(this)
  local error_project = DrawableUtil.getDrawable("android_studio", ColorUtil.getColorSecondary())
  -- 清空文件列表
  FileList = {}

  -- 实例化 LayoutManager
  local layoutManager =
  LinearLayoutManager(
  activity,
  RecyclerView.VERTICAL,
  false)

  -- 实例化 PopupRecyclerAdapter
  adapter_rv=
  PopupRecyclerAdapter(
  activity,
  PopupRecyclerAdapter.PopupCreator({
    getItemCount=function()
      return #FileList
    end,
    getItemViewType=function()
      return 0
    end,
    getPopupText=function(view, position)
      return utf8.sub(FileList[position+1].file_name,1,1)
    end,
    --[[onViewRecycled=function(holder)
      requestManager.clear(holder.Tag.icon)
    end,]]
    onCreateViewHolder=function(parent,viewType)
      local views = {}
      local holder=LuaCustRecyclerHolder(loadlayout(item_layout,views))
      holder.Tag = views
      return holder
    end,
    onBindViewHolder=function(holder,position)
      local view = holder.Tag
      local v = FileList[position+1]
      local v_path = v.path

      view.name.setText(v.file_name)

      if v.img == "Project"
        imageLoader.enqueue(
            ImageRequest.Builder(activity)
              .data(v_path.."/icon.png")
              .target(Target{
                   onError = function()
                      view.icon.setImageDrawable(error_project)
                   end,
                   onSuccess = function(drawable)
                      view.icon.setImageDrawable(drawable)
                   end
              }).build()
        )
       elseif (v.isDirectory and (v.file_name == "mods" or v.file_name == "libs"))
        view.icon.setImageDrawable(res_drawable["folder_mod"])
       else
        view.icon.setImageDrawable(res_drawable[v.img])
      end

      view.contents.onLongClick=function()
        if v.img == "folder_up"
          return
         elseif v.isDirectory
          MainActivity.Public.dirMenu(v_path, v.file_name, position)
         else
          MainActivity.Public.fileMenu(v_path, v.file_name, position)
        end
        return true
      end

      view.contents.onClick=function()

        if not File(v_path).canRead()
          MainActivity.Public.snack(res.string.NoReadPms)
          return
        end

        if v.isDirectory
          PathManager.update_this_dir(v_path)
          filetab.setPath(Bean_Path.this_dir)
          _M.update()
         elseif v.img == "file_img"
          ActivityUtil.new("photo",v_path)
         elseif v.img == "file_zip"
          or v.img == "file_audio"
          or v.img == "file_video"
          or v.img == "file_java"
          or v.img == "file_c_code"
          MainActivity.Public.openFile(v_path, v.file_name)
         elseif v.img == "file_apk"
          MainActivity.Public.InstallApk(v_path)
         else
          -- 来自Recycler的加载请求
          EditorUtil.fromRecy=true
          EditorUtil.load(v_path)
          drawer.closeDrawer(GravityCompat.START);
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
  if not file.canRead() return end
  local fileArray = file.list()

  for _, v : (fileArray) do
    local v = tostring(v)
    local full_path = path.."/"..v
    if File(full_path).isDirectory()
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

  for _, v in ipairs(_FileList)
    DirList[#DirList + 1] = v
  end

  local match = string.match

  local isRoot
  local isProjectDir
  if Bean_Path.this_dir ~= Bean_Path.system_root
    if Bean_Path.this_dir == Bean_Path.app_root_pro_dir
      isProjectDir = true
    end
    FileList = {{isDirectory=true,file_name="...",path=File(Bean_Path.this_dir).getParent(),img="folder_up"}}
   else
    isRoot = true
    FileList = {}
  end
  for k, v in ipairs(DirList)
    local v_path = v.path
    if not isRoot
      k = k + 1
     else
      k = k
    end
    FileList[k] = {}
    local fileinfo = FileList[k]
    fileinfo.path = v_path
    fileinfo.file_name = v.name
    fileinfo.isDirectory = v.isDirectory
    if v.isDirectory
      fileinfo.img = isProjectDir and "Project" or "folder"
     else
      local ext = match(v_path, "%.([^%.]+)$")
      fileinfo.img = suffix_image[ext]
    end
  end
end

local updateCallback = function()
  adapter_rv.notifyDataSetChanged()
  Anim.start()
  swipeRefresh.setRefreshing(false)
end

_M.update=function()
  if executor.getActiveCount() < executor.getMaximumPoolSize() then
    executor.execute(function()
      getList()
      handler.post(updateCallback)
    end)
  end
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
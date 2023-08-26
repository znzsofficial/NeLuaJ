local String = bindClass "java.lang.String"
local Runnable = bindClass"java.lang.Runnable"
local File = bindClass "java.io.File"
local FileInputStream = bindClass "java.io.FileInputStream"
local LuaUtil=bindClass"com.androlua.LuaUtil"
local ZipFile=bindClass"net.lingala.zip4j.ZipFile"
local Executors = bindClass"java.util.concurrent.Executors"
local Handler = bindClass"android.os.Handler"
local Looper = bindClass"android.os.Looper"

local ByteBuffer, FileChannel, Paths, Files, Okio

if SupportProperties.NIO
  ByteBuffer = bindClass "java.nio.ByteBuffer"
  FileChannel = bindClass "java.nio.channels.FileChannel"
  Files = bindClass "java.nio.file.Files";
  Paths = bindClass "java.nio.file.Paths";
 else
  Okio = bindClass "okio.Okio"
end

local _M={}

function _M.create(path,content)
  local file = File(path)
  if not file.exists() then
    file.createNewFile()
    _M.write(path,content,file)
  end
  return _M
end

function _M.write(path,content,file)
  -- 检查文件是否存在
  file = file or File(path)
  if not file.exists()
    print("目标文件不存在")
    return false
  end

  if SupportProperties.NIO then
    -- 使用Nio

    try
      Files.write(Paths.get(path), String(content).getBytes());
      return true
      catch(e)
      return false
    end

   else
    -- 使用okio
    local sink

    try
      sink = Okio.buffer(Okio.sink(file))
      sink.writeUtf8(content)
      -- 刷新缓冲区
      sink.flush()
      return true
      catch(e)
      return false
      finally
      -- 关闭BufferedSink
      sink.close()
    end

  end

end


function _M.read(path)
  local file = File(path);

  if not file.exists() then
    return false
  end

  if SupportProperties.NIO then
    -- 使用Nio
    local fis = FileInputStream(file);
    local fc = fis.getChannel();
    local content
    try
      local buffer = ByteBuffer.allocate(fc.size());
      fc.read(buffer);
      content = String(buffer.array());
      catch(e)
      print("读取失败", e)
      finally
      fc.close();
      fis.close();
      return content;
    end
   else
    -- 使用okio
    local source, bufferedSource, content
    try
      source = Okio.source(file);
      bufferedSource = Okio.buffer(source);
      content = bufferedSource.readUtf8();
      catch(e)
      print("读取失败", e)
      finally
      bufferedSource.close();
      return content;
    end
  end
end


function _M.extract(zipPath)
  local zipFile = ZipFile(zipPath)
  local mainLooper = Looper.getMainLooper()
  local handler = Handler(mainLooper)
  local executor = Executors.newSingleThreadExecutor()
  executor.execute(Runnable{
    run = function()
      local destinationPath = Bean.Path.app_root_dir.."/tmp"
      try
        zipFile.extractAll(destinationPath)
        catch(e)
        print("解压失败")
        finally
        zipFile.close()
      end
      handler.post(Runnable{
        run = function()
          print("解压完成")
        end
      })
    end
  })
  executor.shutdown()
end

function _M.compress(srcFolderPath, destZipFilePath,fileName)
  LuaUtil.zip(srcFolderPath,destZipFilePath,fileName)
end

function _M.remove(Path)
  return File(Path).delete()
end

function _M.rename(old, new)
  try
    local oldFile = File(old)
    local newFile = File(new)
    return oldFile.renameTo(newFile)
    catch(e)
    print("重命名失败", e)
    return false
  end
end

function _M.checkRoot()
  local RootProFile = File(Bean.Path.app_root_pro_dir)
  if not RootProFile.exists()
    RootProFile.mkdirs()
  end
end

function _M.checkBackup()
  local p = luajava.astable(activity.getExternalMediaDirs())[1].getPath()
  Bean.Path.backup_dir = p.."/backups"
  local backup = File(Bean.Path.backup_dir.."/"..os.date("%Y-%m-%d"));
  if not backup.exists() then
    backup.mkdirs();
  end
end

return _M

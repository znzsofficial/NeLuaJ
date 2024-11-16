## FileObserver 示例

```lua
local FileObserver = luajava.bindClass "android.os.FileObserver"
local MyObserver = FileObserver.override{
  onEvent = function(super, event, path)
    switch (event)
     case FileObserver.CREATE
      print("File created: ",super(), event, path)

     case FileObserver.DELETE
      print("File deleted: ",super(), event, path)

     case FileObserver.MODIFY
      print("File modified: ",super(), event, path)
    end
  end
}

local observer = MyObserver("/sdcard/Android")
observer.startWatching()

function onDestroy()
  print("stop")
  observer.stopWatching()
end
```
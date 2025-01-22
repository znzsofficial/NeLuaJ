## Coil 简单使用文档
> Coil 是一个 Android 图片加载库，通过 Kotlin 协程的方式加载图片。特点如下：
> 
> **更快**： Coil 在性能上有很多优化，包括内存缓存和磁盘缓存，把缩略图存保存在内存中，循环利用 bitmap，自动暂停和取消图片网络请求等。
> **更轻量级**： Coil 只有2000个方法（前提是你的 APP 里面集成了 OkHttp 和 Coroutines），Coil 和 Picasso 的方法数差不多，相比 Glide 和 Fresco 要轻量很多。
> **更容易使用**： Coil 的 API 充分利用了 Kotlin 语言的新特性，简化和减少了很多样板代码。更流行： Coil 首选 Kotlin 语言开发并且使用包含 Coroutines， OkHttp， Okio 和 AndroidX Lifecycles 在内最流行的开源库。
---
## 介绍
### 支持的数据类型[¶](https://coil-kt.github.io/coil/getting_started/#supported-data-types "Permanent link")

所有实例支持的基本数据类型包括：`ImageLoader`
-   String
-   HttpUrl
-   Uri (`android.resource`,  `content`,  `file`,  `http`, `https` and  schemes)    
-   File
-   @DrawableRes Int
-   Drawable
-   Bitmap
-   ByteArray
-   ByteBuffer

---

### 支持的图片格式 [¶](https://coil-kt.github.io/coil/getting_started/#supported-image-formats "Permanent link")

所有文件都支持以下非动画文件类型: `ImageLoader`

-   BMP
-   JPEG
-   PNG
-   WebP
-   HEIF (Android 8.0+)
-   AVIF (Android 12.0+)
---
## 开始使用
### 构建  Image Loaders[¶](https://coil-kt.github.io/coil/image_loaders/#image-loaders "Permanent link")

`ImageLoader`s 是执行  [`ImageRequest`](https://coil-kt.github.io/coil/image_requests/)s  [的服务对象](https://publicobject.com/2019/06/10/value-objects-service-objects-and-glue/)。它们处理缓存、数据获取、图像解码、请求管理、位图池、内存管理等。可以使用构建器创建和配置新实例：
```lua
import "coil3.ImageLoader"
local imageLoader = ImageLoader.Builder(activity)
.build()
```
当您创建单个并在整个应用中使用它时，Coil 的性能最佳。这是因为每个都有自己的内存缓存、磁盘缓存和 `.ImageLoader` `ImageLoader` `OkHttpClient`

---

### 图像请求[¶](https://coil-kt.github.io/coil/image_requests/#image-requests "Permanent link")

`ImageRequest`s 是[值对象](https://publicobject.com/2019/06/10/value-objects-service-objects-and-glue/)，它们为  [ImageLoader](https://coil-kt.github.io/coil/image_loaders/)  加载图像提供所有必要信息。

`ImageRequest`可以使用构建器创建：

```lua
import "coil3.request.ImageRequest"
import "coil3.request.ImageRequestsKt"
import "coil3.target.ImageViewTarget"

local builder = ImageRequest.Builder(activity)
.data("https://example.com/image.jpg")
.target(ImageViewTarget(imageView))

ImageRequestsKt.crossfade(builder, true)

local request = builder.build()
```

创建请求后，将其传递给`ImageLoader`排队/执行它：

```lua
imageLoader.enqueue(request)
-- imageLoader 为上面构建的
```
---
### 到此为止，想必你们应该成功创建并将图片显示出来了，接下来再了解点儿其他的。
---
### GIF[¶](https://coil-kt.github.io/coil/gifs/#gifs "Permanent link")

与 Glide 不同，默认情况下不支持 GIF。但是，NeLuaJ+ 已经导入该扩展库。
在构建您的组件注册表时将解码器添加到您的组件注册表中：`ImageLoader`
在 Coil3 中解码器会自动添加到您的组件注册表中。
```lua
import "coil3.ComponentRegistry"
local builder = ComponentRegistry.Builder()
-- 添加 GIF 扩展库
import "android.os.Build"
if Build.VERSION.SDK_INT >= 28 then
  import "coil3.gif.AnimatedImageDecoder"
  builder.add(AnimatedImageDecoder.Factory())
 else
  import "coil3.gif.GifDecoder"
  builder.add(GifDecoder.Factory())
end

import "coil3.request.ImageRequestsKt"
import "coil3.ImageLoader"
local loaderBuilder = ImageLoader.Builder(activity)
ImageRequestsKt.crossfade(loaderBuilder, true)
local imageLoader = loaderBuilder.components(builder.build()) -- 使用 components 方法添加
.build()
```
就是这样！它将使用其文件头自动检测任何 GIF 并正确解码它们。`ImageLoader`

若要转换 GIF 中每一帧的像素数据，请参阅  [AnimatedTransformation](https://coil-kt.github.io/coil/api/coil-gif/coil3.transform/-animated-transformation)。

>**注意**
>
>Coil 包括两个独立的解码器，以支持解码 GIF。 支持所有 API 级别，但速度较慢。 由 Android 的  [ImageDecoder](https://developer.android.com/reference/android/graphics/ImageDecoder)  API 提供支持，该 API 仅适用于 API 28 及更高版本。 比动画WebP图像和动画HEIF图像序列更快，并支持解码。`GifDecoder` `ImageDecoderDecoder` `ImageDecoderDecoder` `GifDecoder`
---
### SVGs[¶](https://coil-kt.github.io/coil/svgs/#svgs "Permanent link")

在构建您的组件注册表时将解码器添加到您的组件注册表中：ImageLoader: 
```lua
import "coil3.ComponentRegistry"
local builder = ComponentRegistry.Builder()
-- 添加 SVG 扩展库
import "coil3.svg.SvgDecoder"
builder.add(SvgDecoder.Factory())

import "coil3.ImageLoader"
imageLoader = ImageLoader.Builder(activity)
.components(builder.build()) -- 与 GIF 添加方法相同，别告诉我你不会两者结合。
.build()
```
Coil 通过在文件的前 1 KB 中查找标记来检测 SVG，这应该涵盖大多数情况。如果未自动检测到 SVG，则可以为请求显式设置：`ImageLoader` `<svg` `Decoder`

**请查看官方文档自行设置**[¶](https://coil-kt.github.io/coil/svgs/#svgs "Permanent link") 

---
### Non-View Targets[¶](https://coil-kt.github.io/coil/migrating/#non-view-targets "Permanent link")
```lua
import "coil3.target.Target"
import "coil3.request.ImageRequest"
local target = Target{
  onStart=function(placeholder)
    -- 在加载开始时调用，处理 placeholder drawable
  end,
  onSuccess=function(result)
    -- 在加载成功时调用，处理成功结果
  end,
  onError=function(error)
    -- 在加载失败时调用，处理错误
  end
}
-- LuaTarget
local target2 = LuaTarget(this, LuaTarget.Listener {
    onStart = function(placeholder)
    end,
    onError = function(error)
    end,
    onSuccess = function(drawable)
    end
})

local request = ImageRequest.Builder(activity)
.data("https://example.com/image.jpg")
.target(target) --设置加载完成后的目标
.build()

imageLoader.enqueue(request)
-- imageLoader 应该是全局创建的，因此直接使用
```
---
### 同步请求
> 感谢此代码提供者：QQ1362883587

```lua
import "coil3.request.ImageRequest"
import "coil3.ImageLoaders_nonJsCommonKt"
import "kotlinx.coroutines.Dispatchers"

local request = ImageRequest.Builder(activity)
.coroutineContext(Dispatchers.Main.immediate)
.data(File/DrawableRes/Drawable/Bitmap/Uri/Byte) -- 请勿使用网络图片，否则会阻塞进程导致崩溃
.build()


local drawable = ImageLoaders_nonJsCommonKt.executeBlocking(
imageLoader, request).getImage().asDrawable(activity.resources)

-- print(drawable)
```
---
### 异步请求
> 感谢此方面代码提供者：QQ1362883587
```lua
xTask(function()
    import "coil3.request.ImageRequest"
    import "coil3.ImageLoaders_nonJsCommonKt"
    local request = ImageRequest.Builder(activity)
    .data(url)
    --.size(300, 300)
    .build()
    local drawable = ImageLoaders_nonJsCommonKt.executeBlocking(
            imageLoader, request).getImage().asDrawable(activity.resources)
    return drawable
  end,
  function(drawable)
    print(drawable)
  end)

activity.loadImage(url, function(drawable)
end)
```
---
### Transformations[¶](https://coil-kt.github.io/coil/transformations/#transformations "Permanent link")

转换允许您在从请求返回图像之前修改图像的像素数据。`Drawable`

默认情况下，Coil 包含 2 种转换：[圆形裁剪](https://coil-kt.github.io/coil/api/coil-core/coil3.transform/-circle-crop-transformation/)和[圆角](https://coil-kt.github.io/coil/api/coil-core/coil3.transform/-rounded-corners-transformation/)。

```lua
-- CircleCropTransformation() -- 圆角
-- RoundedCornersTransformation() -- 圆形裁剪
-- 参数为radius 或 topLeft,topRight,bottomLeft,bottomRight
-- 某种BUG在填入单个转换器时需要也使用List类型
-- 定义一个
import "java.util.ArrayList"
local transformationList = ArrayList()
-- 添加一个转换器
transformationList.add(CircleCropTransformation())
-- 可以继续添加多个

import "coil3.target.ImageViewTarget"
import "coil3.request.ImageRequest"
local request = ImageRequest.Builder(activity)
.data("https://example.com/image.jpg")
.transformations(transformationList) -- 当有多个转换器的时候可以直接添加,不需要List .transformations(transformation1, transformation2, ...)
.target(ImageViewTarget(imageView))

imageLoader.enqueue(request)
```
转换仅修改静态图像的像素数据。向动图图像添加转换会将其转换为静态图像，以便可以正常转换。若要转换动画图像中每一帧的像素数据，请参阅  [AnimatedTransformation](https://coil-kt.github.io/coil/api/coil-gif/coil3.transform/-animated-transformation/)。`ImageRequest`

自定义转换应实现并确保具有相同属性和使用相同转换的两个 s 相等。`equals``hashCode``ImageRequest`

有关详细信息，请参阅  [API 文档](https://coil-kt.github.io/coil/api/coil-core/coil3.transform/-transformation/)。

>注意
>
>如果 Image Pipeline 返回的不是`Drawable`，它将被转换为一个`BitmapDrawable`。这将导致动画可绘制对象仅绘制其动画的第一帧。可以通过设置 来禁用此行为`ImageRequest.Builder.allowConversionToBitmap(false)`

---
### Transitions[¶](https://coil-kt.github.io/coil/transitions/#transitions "Permanent link")

过渡允许您对设置图像请求的结果进行动画处理，即在 `Target` 上。


`ImageLoader` 和 `ImageRequest` 构建器都接受一个过渡。过渡允许您控制成功/错误可绘制对象在 `Target` 上的设置方式。这使您可以对目标视图进行动画处理或包装输入可绘制对象。

默认情况下，Coil 包含两种过渡效果：

-   [CrossfadeTransition.Factory](https://coil-kt.github.io/coil/api/coil-core/coil3.transition/-crossfade-transition/)：从当前可绘制对象淡入到成功/错误可绘制对象。
-   [Transition.Factory.NONE](https://coil-kt.github.io/coil/api/coil-core/coil3.transition/-transition/-factory/-companion/-n-o-n-e)：立即将可绘制对象设置到  `Target`  上，无需动画效果。

```lua
import "coil3.transition.Transition"
import "coil3.transition.CrossfadeTransition"
import "coil3.request.ImageRequest"
import "coil3.target.ImageViewTarget"
local request = ImageRequest.Builder(activity)
.data("https://example.com/image.jpg")

.transitionFactory(Transition.Factory.NONE) -- 不使用过渡效果
.transitionFactory(CrossfadeTransition.Factory(100,false,2,nil)) -- 交叉淡入淡出

-- 但是一般情况下可以直接使用 crossfade 函数
-- 该函数内部设置的上面这两个参数，接收两种值，布尔值和int数值
-- 当传入布尔值时是否启用动画，默认动画时间为100毫秒
-- 传入int数值时，动画时间为传入的数值

.target(ImageViewTarget(imageView))

imageLoader.enqueue(request)
```
查看[CrossfadeTransition 的源代码](https://github.com/coil-kt/coil/blob/main/coil-core/src/main/java/coil/transition/CrossfadeTransition.kt) 以了解如何编写自定义过渡的示例。

有关详细信息，请参阅  [API 文档](https://coil-kt.github.io/coil/api/coil-core/coil3.transition/-transition/)  

--- 
**作者: QQ3070320289 有问题请尝试自行解决，内容有问题请反馈**

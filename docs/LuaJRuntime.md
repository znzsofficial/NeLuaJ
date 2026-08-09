# LuaJ JSE 运行时维护说明

本项目使用 `app/libs/luajpp_nocglib.jar` 作为 LuaJ JSE 基础实现。`filteredLuajppJar` 会移除已由项目源码接管的同名类，避免运行时出现重复定义。当前接管类位于 `app/src/main/java/org/luaj/lib/jse/`。

## 接管兼容性

接管 JAR 类时，以原始 `luajpp_nocglib.jar` 的公开构造器、字段和方法描述符为兼容基线：不删除或收窄既有 public API；新能力以新增方法提供。构建时 `filteredLuajppJar` 必须排除所有已接管类及其内部类，确保运行时只装载项目源码版本。

- `JsePlatform` 仍保留 public 无参构造器和既有 `standardGlobals`、`debugGlobals`、`luaMain` 入口；`sandboxGlobals` 与 `publishClassLoaders` 是新增 API。
- `LuajavaLib.f` 仍为可写 public `HashMap<String, LuaValue>`，仅不再由运行时按类名填充，避免动态 dex 中同名类被错误复用。
- 自定义 ClassLoader 分支继续使用 `Class.forName(name, true, loader)`，保持原有类初始化语义。
- `publishClassLoaders` 在 loader 变更后发布不可变快照；类查找不会并发遍历 `LuaDexLoader` 的可变 `ArrayList`。
- `JavaPackage` 只缓存成功解析的 `JavaClass`，并在 loader generation 变更时清空该 package 节点的缓存。未找到的名称始终作为临时 package node 返回，因此后续 `loadDex()` 可以解析同名动态类，也不会让旧项目的 `JavaClass` 包装继续持有已替换的 `DexClassLoader`。
- 回归测试：`JseBridgeTest.legacyPublicJseApiRemainsInstantiableAndWritable`、`JseBridgeTest.luaJavaLookupUsesCurrentDynamicLoaderList` 与 `JseBridgeTest.classLookupUsesOnlyTheLastPublishedLoaderSnapshot`。

## `JavaClass` 缓存与动态加载

`JavaClass` 以实际的 `Class<?>` 对象作为缓存键，而不是类全名。类名不能唯一标识动态加载的类：不同的 `LuaDexLoader` / `ClassLoader` 可以加载同一个全限定名，且它们在 JVM 中是不同的类型。

缓存实现为：

```java
Map<Class<?>, WeakReference<JavaClass>>
```

- 键和值都不能强引用项目的动态 `ClassLoader`，否则卸载的项目或插件可能无法被回收。
- 对同一个 `Class<?>`，缓存复用对应的 `JavaClass` 包装对象。
- 对不同 ClassLoader 中的同名类，缓存会生成相互独立的包装对象。
- 回归测试：`JseBridgeTest.classLookupKeepsSameNamesFromDifferentLoadersSeparate`。

### 为什么不使用 `ClassValue`

`ClassValue<T>` 是 JDK 提供的按 `Class<?>` 关联惰性计算值的缓存。它有原子安装与并发访问支持，在高频缓存查找场景下通常比带全局锁的 `WeakHashMap` 更合适。

但 Android 的 `java.lang.ClassValue` 从 **API 34（Android 14）** 才开始提供。本项目当前 `minSdk = 26`，且没有启用可为该 API 提供兼容实现的 core-library desugaring；直接引用 `ClassValue` 会使 Android 8 至 Android 13 在运行时缺少该类。因此在最低版本提升至 API 34 前，或确认所需 desugaring 兼容实现可用前，必须保留现有弱引用缓存。

Java 17 的 `jvmToolchain`、`sourceCompatibility` 和 `targetCompatibility` 只控制编译字节码能力，不会改变低版本 Android 设备提供的 framework API。

## Globals 与 AI 沙盒

- `JsePlatform.standardGlobals()` 保留正常 Lua Activity/Service 所需的 `io`、`os`、`package`、`debug`、`require`、`luajava` 与 `import`。
- `JsePlatform.sandboxGlobals()` 仅安装基础 Lua 库、`bit32`、协程、字符串、表、数学、UTF-8 和编译器，并显式移除文件加载、包、调试和 Java 桥接入口。
- `LuaSandbox` 的语法预检和执行均经私有 `:lua_sandbox` `Service` 进入隔离进程；服务以普通 worker 执行代码。主进程和子进程使用同一个单调 deadline，超时 watchdog 会结束该进程，避免不可中断的解析或 Lua 循环残留在 app 进程。
- `LuaSandbox` 必须使用 `sandboxGlobals()`；不能先建立 `standardGlobals()` 再逐项置空，否则遗漏的 `import` 等入口可能重新暴露 Java 绑定。
- 回归测试：`JseBridgeTest.sandboxGlobalsKeepSafeLibrariesAndExcludeJseEntrypoints`。

## JSE IO

项目源码 `JseIoLib` 保留普通 `io.open()` 的读写行为，并在 `io.popen()` 的文件对象关闭时关闭标准输入/输出/错误流并销毁关联进程，避免子进程和文件描述符泄漏。

- 回归测试：`JseBridgeTest.ioOpenKeepsRegularFileReadWriteBehavior`。
- 回归测试：`JseBridgeTest.popenHandlesAreClosable`。
- `io.popen()` 会后台清空未暴露的 stderr；`"w"` 模式还会清空未暴露的 stdout，避免 Lua 只消费单一管道时子进程因另一条管道写满而死锁。
- 回归测试：`JseBridgeTest.popenDrainsStderrBeforeReadingAllStandardOutput`。
- 不支持 `io.popen(..., "rw")`。双向同步 pipe 需要独立异步读写协议，桥接不会暴露一个可能互相等待的半双工文件对象。

## 桥接性能边界

以下优化不改变 Lua 语义，并优先避免为动态 dex 类保留强引用：

- `CoerceJavaToLua.coerce` 对已是 `LuaValue` 的对象直接返回，避免不必要的运行时类型查询和缓存查找。
- 常见 boxed primitive、`String` 与 `Class` 仍使用固定的 `ConcurrentHashMap` coercion 缓存，保证 `xTask` 等工作线程回调可并发转换；任意项目类、数组和 Lua 值不再写入全局 Class 键缓存，避免保留动态 `DexClassLoader`。
- `CoerceLuaToJava` 缓存 primitive、boxed primitive、`String` 和 bootstrap loader 的平台目标类型；动态项目类及其数组的 coercion 仅由活动反射成员持有，不会写入进程级 Class 键缓存。弱 key 不能单独解决该问题，因为 coercion value 本身会反向强引用 target `Class<?>`。
- 自动数值 overload 根据完整的 Lua 64 位整数判断 `byte`、`short`、`char` 与 `int` 范围，绝不依据截断后的 `int` 值让窄类型胜出。需要完全确定的选择时，继续使用 `luajava.constructor(...)` 或 `luajava.method(...)`。
- `JavaInstance` 仅在实际访问 Java 方法后才分配绑定方法缓存；集合 `next()` 使用 LuaJ 的链式 `Varargs`，避免为每个迭代元素创建 `LuaValue[]`。
- `JavaClass.get()` 对 `override`、`new`、`array` 与 `class` 保留 `switch (key.tojstring())`。常见 `LuaString` key 会缓存 Java `String`，因此比多次 Lua 值相等性分派更适合这个 static 成员访问热路径。
- `JavaMethod` 与 `JavaConstructor` 的全局反射包装缓存对 key/value 都使用弱引用。活动的 `JavaClass` 仍强持有自己的反射包装，热路径不受影响；被卸载项目的类不再因全局缓存滞留。
- `JavaClass` 不再在没有 public 构造器的类上额外枚举 `getDeclaredConstructors()`，因为后续仍会过滤为 public。
- Kotlin `callLua` 与 `invokeLua` 共用同一参数转换路径，避免 `callLua` 的 vararg spread 复制。
- `LuaString` 与 `LuaUtf8String` 已接管官方 LuaJ++ 的 64 位 `tointeger` parser，而不是在 `JsePlatform` 包装全局函数。十进制、`0x` 十六进制和显式 base 输入均按低 64 位转换，因此 `tointeger("0xffffffffffffffff")` 与 `tointeger("ffffffffffffffff", 16)` 都返回 `-1`，而不是 `nil`；直接调用字符串对象的 `tointeger` 也保持同一语义。

## Core String 接管

- `LuaString` 与 `LuaUtf8String` 是 runtime ABI 的核心类。接管时以 bundled `luajpp_nocglib.jar` 的公开/受保护成员为兼容基线，仅合入有明确行为依据的修改；Jadx 导出源码不能被视为可整体替换的可信源。
- 官方 64 位 `tointeger` 修复仅需要新增 private parser helper，并改变 `tointeger()` / `tointeger(base)` 的取值路径；`scannumber()`、`tonumber()`、比较、hash、切片和字符串构造必须维持 legacy 行为，除非有独立的字节码或行为验证。
- TextWarrior 编辑器的 `LuaC$UTF8Stream` 会直接调用 `LuaString.encodeToUtf8(char[], int, byte[], int)`，再将编辑器文本送入其 parser。这个方法的错误反编译控制流会截断或错位中文等三字节 UTF-8 字符，进而产生与源码不符的 parser 错误，例如在文件尾附近报 `syntax error '::' expected near end`。实现必须逐个 UTF-16 `char` 输出 1、2 或 3 个 UTF-8 字节，不能使用反编译出的通用多字节循环。
- `LuaString.isValidUtf8()` / `lengthAsUtf8()` 与 `LuaUtf8String.isValidUtf8()` 同样不应照搬反编译出的跳转结构。它们必须正确处理 ASCII、两/三/四字节 UTF-8、无效 continuation byte，以及无效 Unicode code point / surrogate。
- 对 core string 的修改至少回归：全宽 64 位整数、ASCII、中文或其他多字节 Unicode、无效 UTF-8、字符串 table key、拼接、切片，以及 `encodeToUtf8` 的 Unicode 源码往返。当前覆盖：`JseBridgeTest.toIntegerAcceptsFullWidthHexadecimalStrings`、`JseBridgeTest.overriddenStringClassesKeepCoreLuaStringSemantics`、`JseBridgeTest.luaStringUtf8ValidationAndLengthDoNotSkipAsciiOrValidMultibyteCharacters` 和 `JseBridgeTest.luaStringUtf8EncoderPreservesUnicodeSource`。

以下看似可优化的行为刻意保留：

- `Map` 与非 `List` `Collection` 的 `next()` 每次仍从头扫描。缓存迭代器或快照会改变 Lua 遍历期间集合变更可见性。
- 不跳过对 public 反射成员的 `setAccessible(true)`。Android 上此调用可能有成本，但在非 public declaring class 的成员上移除它会改变既有桥接访问能力。
- 不改变零参构造失败时的兼容路径。该路径值得单独修复和测试，但不属于纯性能改动。

性能相关回归覆盖：`JseBridgeTest.boundJavaMethodsAreCachedAndInvokeCorrectly`、`JseBridgeTest.javaClassSpecialMembersDoNotChangeStaticMemberLookup`、`JseBridgeTest.collectionIterationKeepsOrderingAndObservesLaterMutations`、`JseBridgeTest.collectionKeysDoNotPopulateSharedMemberDispatchCaches`、`JseBridgeTest.coercionDoesNotCacheDynamicTargetClasses`、`JseBridgeTest.constructorLookupSkipsClassesWithoutPublicConstructors`、`JseBridgeTest.luaValuesAreReturnedWithoutAdditionalWrapping` 与 `LuaValueExtensionTest`。

## `xTask` 协程边界

`xTask` 的函数式和表式调用均直接在选择的 `Dispatchers.Default` 或 `Dispatchers.IO` 启动，避免先进入 Main dispatcher 再执行一次后台切换。完成回调与错误上报统一切回 `Dispatchers.Main.immediate`，因此 Lua callback、`onError` 和 UI 更新不会在后台线程执行。

- 函数式写法 `xTask(task, callback, dispatcher)` 保留 task 的完整 `Varargs` 结果给 callback。
- 表式写法 `xTask { task = ..., callback = ..., dispatcher = ... }` 保持既有行为，只将 task 的第一个返回值传给 callback。
- 返回的 `LuaJobWrapper` 保留 public `job` 属性，新增 `cancel()` 与 `isActive()`；取消时会释放对 `Job` 的引用。
- `lifecycleScope` 会在 Activity 销毁时取消仍在运行的任务。
- 回归测试：`LuaJobWrapperTest.cancelCancelsAndReleasesTheJob`。

## Lua 与 Kotlin 类

Lua Java bridge 通过 Kotlin 生成的 JVM API 工作，不依赖 `kotlin-reflect`：

- `luajava.kotlinObject(classNameOrClass)` 返回 Kotlin `object` 的 singleton，封装生成的 `INSTANCE` 字段。
- `luajava.kotlinCompanion(classNameOrClass)` 返回 Kotlin companion object，封装生成的 `Companion` 字段。
- companion 方法标注 `@JvmStatic` 后可继续通过 `luajava.bindClass(...).method(...)` 直接调用；未标注的方法通过 `kotlinCompanion(...).method(...)` 调用。
- Lua 中 Java/Kotlin 成员统一使用点调用，不支持冒号调用，避免将 self 作为额外 Java 参数。
- 默认参数不会自动变成 Java 重载。需要 Lua 省略参数时，Kotlin API 应使用 `@JvmOverloads`；否则 Lua 必须传入完整参数列表。
- 回归测试：`JseBridgeTest.luaCanAccessKotlinObjectsCompanionsAndJvmStaticMethods` 与 `JseBridgeTest.kotlinInteropHelpersRejectMissingGeneratedMembers`。

## LuaJava 便利 API

新增 API 保持在现有 `luajava` 命名空间，只使用既有 Java bridge 的 coercion 规则：

- `luajava.toTable(value[, recursive])` 是 `astable` 的可读别名。传入 Lua table 时原样返回；默认只转换 Java 数组、Collection、Map、`JSONObject` 或 `JSONArray` 的第一层，传 `true` 才递归转换嵌套集合或 JSON 容器。
- `luajava.toList(table)` 与 `luajava.toSet(table)` 读取 Lua table 的 array part（`1..#table`），分别生成 Java `ArrayList` 和保留插入顺序的 `LinkedHashSet`。
- `luajava.toMap(table)` 转换全部 Lua table entry，生成按当前 Lua table 遍历顺序填充的 Java `LinkedHashMap`。
- `luajava.constructor(classOrName, parameterTypes)` 返回由精确 public 参数类型选定的可调用构造器。`parameterTypes` 是 Lua array table，元素可为 class、`JavaClass` 或类名；primitive 可写成 `"int"`、`"long"` 等，数组类名使用 `"java.lang.String[]"` 形式。
- `luajava.method(targetOrClass, name, parameterTypes)` 返回由精确 public 参数类型选定并绑定 target 的可调用方法。target 为实例时选择实例方法；target 为 class 或类名时只能选择 static 方法。它是自动重载评分无法消除歧义时的确定性入口，不改变普通 `object.method(...)` 的现有行为。
- `luajava.iterate(value)` 返回可用于 Lua 泛型 `for` 的独立 stateful iterator，支持 Java 数组、`Map`、`Iterable`、`Iterator` 与 Kotlin `Sequence`。非 Map 返回 `index, value`，index 从 0 开始；Map 返回 `key, value`。它在创建时取得 Java iterator，因此集合并发修改的语义不同于 userdata 的 `next()`。
- `#` 支持 Java `Map` 和全部 `Collection`，包括 `Set`；Java array 仍由 `JavaArray` 提供长度。
- LuaJ++ 现有的 `import alias "className"` 语法继续提供别名；不新增第二套 import 调用约定。
- 这些 API 不猜测 table 的用途、不自动递归，也不引入 `kotlin-reflect`。
- 回归测试：`JseBridgeTest.luaConvenienceCollectionConversionsKeepExpectedValues`、`JseBridgeTest.toTableUsesShallowConversionUnlessRecursionIsRequested`、`JseBridgeTest.explicitConstructorAndMethodSelectionBypassOverloadScoring`、`JseBridgeTest.javaIteratorSupportsMapsArraysIteratorsAndKotlinSequences` 与 `JseBridgeTest.collectionLengthIncludesSets`。

## 本地单元测试

遗留 Luaj++ JAR 缺少部分 `StackMapTable` 信息。ART 可以处理其 DEX 输出，但桌面 JDK 验证会失败，因此 Gradle 的本地 `Test` 任务使用 `-noverify`。该选项仅用于本地 JVM 单元测试；Android 构建仍可能出现来自遗留 JAR 的 D8 stack-map 警告。

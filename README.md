# NeLuaJ
 
### 项目支持
QQ群组：603327362

未来将在这里发布最新版本，也欢迎在这里提交建议和反馈。

### 前言
**建议有一定安卓开发基础的用户使用。**

如果你认为本编辑器不自带中文、模板，或从其它编辑器复制来的代码无法运行让你困惑，那么你不适合使用它。如果你仅从QQ群或小论坛里接触编程相关的内容，那你同样不适合使用它。


### LuaJ++的特点
全局环境中默认导入了 http,json,print,printf,res,call,file,thread,timer,dump,xTask等模块，可以直接使用


### 值得注意的地方

布局表可以使用类似**AndroLua+**的写法

init.lua 新增NeLuaJ_Theme配置，允许直接设置编辑器内置的主题

setContentView 方法支持传入布局表或加载过的视图

补全了LuaActivity继承AppCompatActivity的一些方法，增加了更多新特性。

LuaFragment 新增更多方法，且迁移到AndroidX

由于welcome**不再自动申请**全部权限，为符合Android设计运行时权限的初衷，请开发者自行实现权限申请和申请回调逻辑。

welcome 使用多线程解压

删除了内置的 android.widget 包，并移除了 PageView 相关适配器

实现了类似 FusionApp2 的导入分析，此部分作者QQ:3070320289

将AndroLua+的部分Adapter移动到了**com.androlua.adapter**下，实际开发时请**留意Java方法浏览器**。

loadlayout 支持更多属性，例如textStyle, layout_anchor, pages (for ViewPager) 等

新增 xTask 函数，使用 Kotlin 协程实现

##依赖
AppCompat 1.7.0-alpha03

Material 1.11.0

Lottie 6.3.0

Glide 4.16.0

Okhttp 4.11.0

Zip4J 2.11.5

appiconloader-glide 1.5.0

android-fastscroll 1.2.0

com.drakeet.drawer 1.0.3


###感觉不如原神

你说的对，但是《​NeLuaJ+》是由NekoLaska
自主研发的一款全新的在安卓使用Lua语言开发应用的工具。
游戏发生在一个被称作「Android」的幻想世界，
在这里，被神选中的人将被授予「语法糖」，
导引Java API之力。
你将扮演一位名为「程序员」的神秘角色，
在自由的旅行中邂逅性格各异、能力独特的同伴们，
和他们一起击败Bug，找回失散的类库——同时，
逐步发掘「LuaJ++」的真相。​

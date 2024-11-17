### 项目支持

QQ群组：603327362

未来将在这里发布最新版本，也欢迎在这里提交建议和反馈。

### 前言

**建议有一定安卓开发基础的用户使用。**

如果你认为本编辑器不自带中文、模板，或从其它编辑器复制来的代码无法运行让你困惑，那么你不适合使用它。如果你仅从QQ群或小论坛里接触编程相关的内容，那你同样不适合使用它。

### 值得注意的地方

init.lua 新增NeLuaJ_Theme配置，允许直接设置编辑器内置的主题

setContentView 方法支持传入布局表或加载过的视图

补全了LuaActivity 继承 AppCompatActivity 的一些方法，增加了更多新特性。

LuaFragment 新增更多方法，迁移到AndroidX

由于welcome**不再自动申请**全部权限，为符合Android设计运行时权限的初衷，请开发者自行实现权限申请和申请回调逻辑。

Welcome 使用多线程解压，过程中会将 assets 内所有 dex 文件设为仅读

删除了内置的 android.widget 包，并移除了 PageView 相关适配器

实现了类似 FusionApp2 的导入分析，此功能作者QQ:3070320289

布局助手作者QQ：2241056127

将AndroLua+的部分Adapter移动到了**com.androlua.adapter**下，实际开发时请**留意Java方法浏览器**。
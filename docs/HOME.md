# 首页、工程与编辑器实现

本页描述当前调用链和限制，不是视觉验收记录。使用方法见[首页指南](../app/src/main/assets/res/doc/home_zh.html)，设备验收见 [HOME_VALIDATION.md](./HOME_VALIDATION.md)，兼容底线见 [MAINTENANCE.md](./MAINTENANCE.md)。下文 Lua 路径相对 `app/src/main/assets/`。

## 页面与模块

| 模块 | 职责 |
|------|------|
| `main.lua` → `activities/home/HomeActivity.lua` | 启动首页、权限恢复、命名页面宿主 |
| `res/layout/home_layout.lua` | 四个目的地、颜色、原生壳接线 |
| `app/src/main/java/com/nekolaska/home/HomePages.kt` | 稳定页面键、item ID 与宽度策略 |
| `app/src/main/java/com/nekolaska/home/HomeShellView.kt` | 单个 ViewPager2、底栏/导航轨、可见页刷新合并 |
| `app/src/main/java/com/nekolaska/home/HomePageFragment.kt` | arguments 页面标识、视图重建与延后滚动恢复 |
| `activities/home/ProjectsPage.lua` | 工程搜索、最近打开、目录入口、恢复状态与 RecyclerView |
| `activities/home/ConversationsPage.lua` | 跨工程会话元数据列表、新建/打开/删除与 RecyclerView |
| `activities/home/HelpPage.lua`、`activities/home/SettingsPage.lua` | 帮助和设置；销毁时释放缓存视图，重建时重新接线 |
| `activities/home/HomeRows.lua` | 主线程列表快照比较、复用未变绑定表、连续区间通知 |
| `mods/project/HomeProjects.lua` | 后台只读工程扫描与过滤、目录验证 |
| `mods/project/RecentProjects.lua` | 真实打开时间记录，非目录 mtime 推断 |
| `activities/main/CreateProject.lua` | 工程脚手架；创建通知与宿主打开动作分离 |
| `activities/main/MainActivity.lua` | 编辑器装配、工作区恢复、安全离开与待办导航消费 |
| `mods/utils/ActivityUtil.lua` | 路由、带身份的待办导航、成功确认消费 |
| `mods/editor/LeaveGuard.lua` | 保存结果判定、重试/取消/明确放弃、过期确认保护 |
| `mods/project/ProjectContext.lua`、`activities/main/Workspace.lua` | 工程/浏览目录/文件快照与工程级标签、光标持久化 |
| `mods/project/ProjectMenu.lua`、`mods/project/ProjectPersistence.lua` | 工程菜单、编辑器占用门禁与可恢复改名 |

## 创建与打开

创建模块调用 `onCreated(path, openAfter)` 通知，再按勾选意图调用可选 `openProject(path)`。首页提供路由，编辑器宿主未提供该回调时保留原地切换逻辑。创建成功和打开成功分别反馈，不能因宿主回调失败谎报完整交接。

普通打开工程/目录不强制载入 `main.lua`，也不覆盖无关 pending 请求；编辑器恢复已有工作区。只有新建工程的“创建后打开”显式请求 `open_file` 指向新 `main.lua`。当前目录入口是直接打开已有可读目录，不提供 ZIP 导入或复制/覆盖导入。

## 列表加载与状态

首页使用统一的 20dp 页边距、24dp 分区间隔、12dp 列表行间隔、16dp 卡片圆角/内边距。项目页主操作在标题右侧，目录入口在搜索旁；会话页只保留一个新建入口。重试/授权只在相应失败状态出现。`activities/home/HomeStyle.lua` 统一标题、操作层级与列表页壳；AppBarLayout 随列表滚动收起头部，避免横屏/大字体时固定头部挤没列表。`LuaRecyclerAdapter` 用 RecyclerView.LayoutParams 加载根行，确保布局表的 margin 生效，不以额外嵌套 ScrollView 牺牲回收。

- 工程扫描和配置读取通过 IO 任务执行，配置元信息按 mtime 缓存；图标交给现有 Adapter/Coil 加载。扫描只检查改名日志，不自动恢复迁移。
- 项目、会话、帮助三页均使用 `LuaRecyclerAdapter` 回收可见行；帮助目录先准备数据，不再一次创建整个目录的卡片 View。
- 项目和会话的 `HomeRows` 比较独立、只读的快照，不变时不创建新绑定表或通知 Adapter；变化时保留相同 key/内容的绑定，用共享前后缀确定一个连续区间，发出 changed 或 remove/insert 通知。它不是完整 DiffUtil，不保证移动动画或最小编辑序列。不要在提交后原地修改其源快照。
- 刷新开始/权限错误只更新状态，不重新提交旧列表。有成功数据后不重复展开/收起 loading 文案，减少 AppBar 高度变化；“最近打开”仅在内容或排序变化时重建卡片，未变时保留水平滚动位置。
- 搜索/排序文本在后台扫描时预先归一化；空搜索直接使用只读原列表，同一组匹配结果不会触发行重绑定。同名项目按路径补齐排序，避免不稳定顺序引发多余更新。
- 项目搜索匹配目录名、应用名和包名；最近打开来自单独持久化记录，不把目录时间当用户操作记录。
- 权限、加载、读取失败、空列表和无搜索结果分别表达；刷新失败保留上次成功结果，不把损坏索引伪装成空会话。
- 会话页通过 `ConversationStore.loadIndex(force)` 读取磁盘元数据，正常索引读取不加载正文；首次旧数据迁移仍需读取并写出旧记录。详情在 [AIAgent.md](./AIAgent.md)。

页面 `pause()` 取消任务并作废 generation；`dispose()` 还释放视图与 Adapter 引用。结果只在页面、工程和 generation 仍匹配时应用。

## 导航、返回与恢复

`ActivityUtil.setPending` 写入带身份、时间和 payload 的请求；编辑器验证目标与打开结果后才确认消费。失败请求保留，可显式重试或忽略；身份比较防止迟到回调清掉新请求。旧调用入口保留，但新交接不应使用先清除再执行的消费方式。

首页根 Back 交给系统。编辑器 Back 先关闭抽屉/搜索，再经统一离开保护：保存返回 `true` / `"same"` 才可正常离开；失败、nil 或异常保留缓冲区。放弃必须二次确认且快照仍是同一文件和正文。菜单与返回使用同一保护，`onPause` 不弹阻断对话框。

首页按实际宽度在 600dp 阈值切换底栏/导航轨，不重建 pager；编辑器平板模式把保存偏好和当前有效宽度分开，窄窗临时回退抽屉，不改写偏好。

Fragment 通过稳定 arguments 页面键向新 Activity 的命名 Lua 宿主重新建页，不持久化 Lua closure。关键视图有稳定 ID；列表 LayoutManager 状态与 ScrollView 偏移等待 `__homeUi.pageContentReady(key)` 后恢复，避免空 Adapter 提前恢复导致位置丢失。真实系统回收、主题重建与横竖屏恢复仍需设备验证。

## 工程改名与数据保护

`ProjectPersistence` 为顶层工程改名保存单个 durable journal，迁移工作区、会话工程归属、最近打开和 Agent 根目录别名，**最后才移动工程目录**。原工作区、会话快照及存储文件保留；多文件迁移不宣称事务性。

显式前台重试通过 `ProjectMenu.resumePendingRename()` 检查占用后执行。后台扫描只读 `pendingRename()`；不能在 IO 刷新时擅自继续改名。返回的 `detail` 包含阶段、错误、可重试性与完成状态；最终日志清理失败可能 `ok=false` 但 `completed=true`，不能伪报全部成功。

已知占用的工程先关闭编辑器再改名，避免标签闭包/自动保存写回旧路径。跨 Activity 检查保守阻止可见的活动编辑器，但当前 registry 只公开最新实例，不是完整多窗口/跨进程租约。

Agent 根存储通过别名保留，**不自动改写旧 ChangeSet 内嵌绝对路径、scope 或未定义的子目录哈希桶**。旧文件撤销历史不能承诺在改名后继续重放；日志/备份暂无自动垃圾回收，应在确认恢复前保留。

## 验证边界

Lua 套件验证实际模块与宿主替身，JVM 测试覆盖页面身份/宽度策略等纯逻辑；它们不证明 TalkBack 播报、真实 FragmentManager 恢复、滚动流畅度或 Material 视觉效果。当前没有自动草稿，保存失败后的未落盘正文仍在内存，不保证进程死亡后恢复。

性能回归用操作计数而非桌面耗时冒充真机性能：`TestHomeRows` 检查不变快照零绑定/通知及随机区间回放；`TestHomeProjects` 检查不变刷新零额外 View/占位图创建；`TestHomeConversations` 用大量索引行检查局部更新；`TestHomeShell` 检查帮助壳的加载次数不随目录条目数增长。磁盘扫描/索引读取和线性快照比较仍会执行，首次绑定与设置页布局也不是零成本；冷启动的类名预加载尚未在真机定位。本轮没有设备帧时间、内存或提速百分比保证，采样步骤见 [HOME_VALIDATION.md](./HOME_VALIDATION.md)。

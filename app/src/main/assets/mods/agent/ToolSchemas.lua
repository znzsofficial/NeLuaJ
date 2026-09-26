-- Agent 内置工具 schema（纯数据；由 mods/agent/AgentChat 组合根引用）。
-- 与 ToolExecutor 的实现和 AgentTurn 的执行语义保持同名。
return {
  {
    type = "function",
    ["function"] = {
      name = "create_file",
      description = "创建或覆盖文件。路径可以是绝对路径或相对于当前项目的路径。.lua 文件保存前会自动做语法预检，失败则不创建并返回错误。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径，如 main.lua 或 /sdcard/test.lua" },
          content = { type = "string", description = "文件内容" },
        },
        required = { "path", "content" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "create_folder",
      description = "创建文件夹（含缺失的父目录）。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件夹路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "delete_file",
      description = "删除文件。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要删除的文件路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "delete_folder",
      description = "删除文件夹及其所有内容。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要删除的文件夹路径" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "读取文件内容。大文件按行分段读取：offset 指定从第几行开始（1 起），max 限制返回最大字符数（默认 8000）。返回带行号内容，便于后续 apply_patch。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径" },
          offset = { type = "integer", description = "起始行号（可选，默认 1）" },
          max = { type = "integer", description = "返回最大字符数（可选，默认 8000）" },
        },
        required = { "path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "read_files",
      description = "批量读取多个文件内容（一次调用读多个文件，减少往返）。paths 为文件路径数组，最多 20 个。每个文件都按行号分页返回，用 offset/max 控制分页。总返回有上限，超出会截断。某个文件读取失败不影响其他文件。",
      parameters = {
        type = "object",
        properties = {
          paths = { type = "array", items = { type = "string" }, description = "要读取的文件路径列表" },
          offset = { type = "integer", description = "起始行号（可选，默认 1）" },
          max = { type = "integer", description = "每个文件返回最大字符数（可选，默认 4000）" },
        },
        required = { "paths" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "search_in_files",
      description = "在目录内按内容递归搜索（类似 grep）。返回 路径:行号: 内容 列表。用于快速定位某段代码/字符串出现的位置。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "搜索目录（可选，默认当前项目目录）" },
          pattern = { type = "string", description = "要搜索的文本，普通子串匹配（非正则）" },
          max = { type = "integer", description = "最大结果数（可选，默认 50）" },
          ignore_case = { type = "boolean", description = "忽略大小写（可选，默认 false）" },
        },
        required = { "pattern" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "check_lua_syntax",
      description = "使用 NeLuaJ+ 内置 LuaJ++ 解析器只编译检查 Lua 代码语法，不执行代码、无副作用。适合修改后快速检查语法；检查通过不代表运行时逻辑正确。",
      parameters = {
        type = "object",
        properties = {
          code = { type = "string", description = "要检查的完整 Lua/LuaJ++ 代码" },
        },
        required = { "code" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "run_lua",
      description = "在受限沙盒中运行 Lua 代码（语法检查、捕获 print/chunk 返回值、超时保护）。首次调用前，若当前上下文尚无沙盒文档，必须先用 read_file 读取 res/doc/sandbox_zh.html（英文对话读取 res/doc/sandbox_en.html），不得猜测 API。沙盒提供 json、codec（Base64/Hex/URL）、hash.sha256、inspect、assert_equal 和受控 http.request；联网前必须在 network_hosts 中逐个声明 HTTPS 主机。不含 io/package/luajava/require，不能访问文件、私网或 Android。用于验证算法、数据转换、HTTP API 和纯 Lua 逻辑。是否直接执行由“自动运行沙盒代码”设置决定；带联网主机时还需同时开启“自动批准网络请求”。",
      parameters = {
        type = "object",
        properties = {
          code = { type = "string", description = "要运行的完整 Lua 代码（纯 Lua，可用 print 输出结果）" },
          timeout = { type = "integer", description = "超时毫秒数（可选，默认 3000，上限 8000）" },
          network_hosts = {
            type = "array",
            items = { type = "string" },
            description = "代码通过 http.request 访问的精确 HTTPS 主机名（可选，最多 8 个；禁止 IP、localhost 和私网）。不联网时省略",
          },
        },
        required = { "code" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "run_project",
      description = "运行当前工程的 Lua 入口脚本（真实 Android 环境，非沙盒），并在等待窗口内捕获未捕获异常（读取崩溃日志目录的新增记录）。用于修改代码后验证运行时行为。脚本自身的 onError 捕获或正常运行的界面效果不会写入日志；启动的是独立界面，不会阻塞本会话。每次调用都需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "入口脚本路径（可选；默认依次取当前打开文件、工程 init.lua、main.lua 中第一个存在的）" },
          wait_ms = { type = "integer", description = "等待崩溃记录的时长毫秒数（可选，默认 4000，范围 1000-10000）" },
        },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "build_project",
      description = "调用 NeLuaJ+ 打包器（Builder）对当前工程进行打包配置与构建。调用前会自动预检 init.lua 语法与必要字段（app_name、package_name、ver_name 等），并保存当前编辑器内容。启动独立的打包器界面，每次调用都需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "工程目录路径（可选，默认当前工程根目录）" },
        },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "fetch_url",
      description = "从沙盒外读取公开 HTTPS 文本资源。仅支持 GET/HEAD，不接受自定义请求头、单独的认证参数、Cookie 或请求体；URL 查询参数会原样发送。禁止 IP、localhost、私网、自签名证书和非 443 端口。是否确认由“自动批准网络请求”设置决定，重定向会重新校验。适合读取公开网页、文档和 JSON/XML API。",
      parameters = {
        type = "object",
        properties = {
          url = { type = "string", description = "公开 HTTPS URL" },
          method = { type = "string", enum = { "GET", "HEAD" }, description = "请求方法（可选，默认 GET）" },
          timeout = { type = "integer", description = "总超时毫秒数（可选，默认 8000，范围 1000-15000）" },
          max_chars = { type = "integer", description = "最多返回的正文字符数（可选，默认 12000，上限 50000）" },
        },
        required = { "url" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "apply_patch",
      description = "对现有文件应用增量修改。支持 SEARCH/REPLACE 块格式和 Unified Diff 格式。优先使用此工具而非 create_file 来修改已有文件。.lua 文件保存前会自动做语法预检，失败则不应用并返回错误。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要修改的文件路径" },
          patch = { type = "string", description = "补丁内容。推荐 SEARCH/REPLACE 块格式：每块用 <<<<<<< SEARCH / ======= / >>>>>>> REPLACE 包裹。也支持 unified diff 格式。" },
        },
        required = { "path", "patch" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "replace_in_file",
      description = "简单字符串替换：把文件中的指定文本直接替换为新文本（普通匹配，非正则）。适合小改动，比 apply_patch 更不容易失败。count 可选限制替换次数（默认替换全部）。.lua 文件保存前会自动做语法预检，失败则不应用并返回错误。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "要修改的文件路径" },
          old = { type = "string", description = "要查找的原文（普通字符串，区分大小写）" },
          new = { type = "string", description = "替换后的新文本" },
          count = { type = "integer", description = "最多替换次数（可选，默认全部）" },
        },
        required = { "path", "old", "new" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "list_dir",
      description = "列出目录下的文件和文件夹。recursive=true 时递归列出子目录（自动跳过 .git/build/node_modules 等，pattern 可按名称过滤）。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "目录路径，默认当前项目目录" },
          recursive = { type = "boolean", description = "是否递归列出子目录（可选，默认 false）" },
          pattern = { type = "string", description = "按名称过滤（普通子串匹配，可选）" },
        },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "append_file",
      description = "向现有文件末尾追加内容（不覆盖已有内容）。文件不存在时创建。适合写日志、追加配置等。.lua 文件在写入前会拼接已有内容整体做语法预检，失败则不追加并返回错误。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "文件路径" },
          content = { type = "string", description = "要追加的内容" },
        },
        required = { "path", "content" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "rename_file",
      description = "重命名或移动文件/文件夹（源路径 → 新路径，同目录改名或跨目录移动均可，不支持跨存储设备）。操作需要用户确认。",
      parameters = {
        type = "object",
        properties = {
          path = { type = "string", description = "原路径" },
          new_path = { type = "string", description = "新路径（目标路径）" },
        },
        required = { "path", "new_path" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "update_todos",
      description = "维护当前会话的任务计划（全量替换，每次传入完整列表）。任务含 3 个及以上步骤时先建立计划，每完成一步更新条目状态，全部完成后把所有条目标记为 completed。两步以内的任务不需要使用。",
      parameters = {
        type = "object",
        properties = {
          todos = {
            type = "array",
            description = "完整的任务列表；传空数组表示清空计划",
            items = {
              type = "object",
              properties = {
                content = { type = "string", description = "任务条目内容，简洁的动词短语" },
                status = { type = "string", enum = { "pending", "in_progress", "completed" }, description = "pending 待办 / in_progress 进行中 / completed 已完成" },
              },
              required = { "content", "status" },
            },
          },
        },
        required = { "todos" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "run_subtask",
      description = "委派子代理在隔离上下文中独立完成一个调查或实现任务，并取回精简结果。子代理拥有完整的文件与运行工具，但不继承当前对话历史，任务描述必须自包含（目标、相关路径与背景、期望的产出形式）。适合多文件调研、问题定位、方案对比等需要大量工具往返的工作；简单任务直接自己做。",
      parameters = {
        type = "object",
        properties = {
          task = { type = "string", description = "自包含的任务描述" },
          lightweight = { type = "boolean", description = "用辅助模型执行（适合纯调研任务，默认 false 用当前模型）" },
        },
        required = { "task" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "get_env_info",
      description = "获取当前运行环境信息（Android 版本、Lua 版本、项目目录、API 配置等），用于给出贴合环境的建议。",
      parameters = {
        type = "object",
      },
    },
  },
}

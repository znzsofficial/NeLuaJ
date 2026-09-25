local ASSETS = ASSETS or "app/src/main/assets/"

-- Markdown.splitCodeBlocks 行为测试：纯字符串切分，独立 LuaJ 运行时。
-- renderMarkdown 依赖 HtmlCompat（延迟绑定，Android 环境），挂架不调用它。
local MD = assert(loadfile(ASSETS .. "mods/agent/Markdown.lua"))()

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

-- 1. 纯文本
local parts = MD.splitCodeBlocks("普通文本")
check("plain text single part", #parts == 1 and parts[1].type == "text"
  and parts[1].text == "普通文本")

-- 2. 文本 + 代码块
parts = MD.splitCodeBlocks("前文\n```lua\nprint(1)\n```\n后文")
check("text+code+text", #parts == 3 and parts[1].text == "前文\n"
  and parts[2].type == "code" and parts[2].lang == "lua" and parts[2].code == "print(1)"
  and parts[3].text == "\n后文", #parts)

-- 3. 无语言标记
parts = MD.splitCodeBlocks("```\ncode\n```")
check("no lang block", #parts == 1 and parts[1].type == "code" and parts[1].lang == ""
  and parts[1].code == "code")

-- 4. 未闭合代码块 → 整段按原文返回
parts = MD.splitCodeBlocks("开头\n```lua\nprint(1)")
check("unterminated block", #parts == 2 and parts[1].type == "text"
  and parts[2].text == "```lua\nprint(1)")

-- 5. 开头即代码块（无前导文本）
parts = MD.splitCodeBlocks("```js\nx\n```\n尾")
check("leading code block", #parts == 2 and parts[1].type == "code"
  and parts[1].lang == "js" and parts[2].text == "\n尾")

-- 6. 多个代码块
parts = MD.splitCodeBlocks("```a\n1\n```\nmid\n```b\n2\n```")
check("two code blocks", #parts == 3 and parts[1].code == "1"
  and parts[2].type == "text" and parts[3].code == "2", #parts)

-- 7. 行内反引号不误判
parts = MD.splitCodeBlocks("这是 `code` 行内")
check("inline backticks untouched", #parts == 1 and parts[1].type == "text")

-- 8. 嵌套 ``` 的现状行为（原版固有语义，锁定防回归）：
--    第一行 ``` 开块，"```nested" 行被当作闭合标记 → 空代码块，
--    "nested" 与尾部 ``` 均按普通文本返回
parts = MD.splitCodeBlocks("```\n```nested\n```")
check("nested markers current behavior", #parts == 3
  and parts[1].type == "code" and parts[1].code == ""
  and parts[2].type == "text" and parts[2].text == "nested\n"
  and parts[3].type == "text" and parts[3].text == "```", #parts)

-- 9. 空内容
parts = MD.splitCodeBlocks("")
check("empty content", #parts == 0)

-- 10. 表格行解析与分隔行识别
local cells = MD.splitTableRow("| 名称 | 值 | 备注 |")
check("split table row", #cells == 3 and cells[1] == "名称" and cells[2] == "值" and cells[3] == "备注", #cells)
local cells = MD.splitTableRow("|a||b|")
check("split keeps empty cells", #cells == 3 and cells[1] == "a" and cells[2] == "" and cells[3] == "b", #cells)
check("separator detected", MD.isTableSeparator("| --- | :---: | ---: |") == true)
check("separator plain dashes", MD.isTableSeparator("|---|---|") == true)
check("non-separator rejected", MD.isTableSeparator("| a | b |") == false)
check("non-pipe rejected", MD.isTableSeparator("---") == false)
check("bad cell rejected", MD.isTableSeparator("| --- | x |") == false)

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end

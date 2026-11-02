--- 针对阶段三 Markdown AST 解析器的独立脱水单元测试
local assets = ASSETS or "app/src/main/assets/"
local AST = assert(loadfile(assets .. "mods/agent/markdown/MarkdownAST.lua"))()

local total, passed = 0, 0
local function check(desc, cond, extra)
  total = total + 1
  if cond then
    passed = passed + 1
    print("  PASS  " .. desc)
  else
    print("  FAIL  " .. desc .. (extra and (" -> " .. tostring(extra)) or ""))
    os.exit(1)
  end
end

-- 1. 表格解析与转义管道符测试
local tableLine = "| Name | Path | Description |"
local cells = AST.splitTableRow(tableLine)
check("splitTableRow normal", #cells == 3 and cells[1] == "Name" and cells[2] == "Path" and cells[3] == "Description")

local escapedLine = "| grep \\| sort | regex | match |"
local escCells = AST.splitTableRow(escapedLine)
check("splitTableRow escaped pipe", #escCells == 3 and escCells[1] == "grep | sort" and escCells[2] == "regex")

-- 2. 块级分块与代码块解析
local md = [[
前置段落说明。

```lua
local a = 1
local b = 2
```

后置段落说明。
]]

local blocks = AST.parseBlocks(md)
check("blocks count 3", #blocks == 3)
check("block 1 text", blocks[1].type == "text" and blocks[1].text:find("前置段落", 1, true) ~= nil)
check("block 2 code", blocks[2].type == "code" and blocks[2].lang == "lua" and blocks[2].code:find("local a = 1", 1, true) ~= nil)
check("block 3 text", blocks[3].type == "text" and blocks[3].text:find("后置段落", 1, true) ~= nil)

-- 3. 独立表格结构解析
local mdWithTable = [[
介绍文本：

| 模块 | 状态 | 备注 |
| :--- | :---: | ---: |
| 调度器 | 完成 | P0 |
| 排版引擎 | 进行中 | P2 |

结束总结。
]]

local tableBlocks = AST.parseBlocks(mdWithTable)
check("table blocks count 3", #tableBlocks == 3)
check("table block type", tableBlocks[2].type == "table")
check("table headers", #tableBlocks[2].headers == 3 and tableBlocks[2].headers[1] == "模块")
check("table alignments", tableBlocks[2].alignments[1] == "left" and tableBlocks[2].alignments[2] == "center" and tableBlocks[2].alignments[3] == "right")
check("table rows count", #tableBlocks[2].rows == 2)
check("table row 1 data", tableBlocks[2].rows[1][1] == "调度器" and tableBlocks[2].rows[1][2] == "完成")

-- 4. 流式未闭合代码块容错
local unclosedMd = "```python\nprint('hello')\n"
local unclosedBlocks = AST.parseBlocks(unclosedMd)
check("unclosed code block recognized", #unclosedBlocks == 1 and unclosedBlocks[1].type == "code" and unclosedBlocks[1].unclosed == true)

local raw = "| A | B |\n| --- | --- |\n| 1 | 2 |"
local rawBlock = AST.parseBlocks(raw)[1]
check("fallback preserves exact table source", rawBlock.raw == raw)
check("fallback source reparses as table", AST.parseBlocks(rawBlock.raw)[1].type == "table")
local optionalPipes = AST.parseBlocks("A | B\n--- | :---:\n1 | 2")[1]
check("table without outer pipes", optionalPipes.type == "table" and optionalPipes.rows[1][2] == "2")
check("mismatched header separator is text", AST.parseBlocks("A | B\n--- | --- | ---")[1].type == "text")
local tilde = AST.parseBlocks("~~~lua\nprint(1)\n~~~")[1]
check("tilde fences supported", tilde.type == "code" and tilde.code == "print(1)")
local nested = AST.parseBlocks("````md\n```lua\nx\n```\n````")[1]
check("shorter fences remain code", nested.type == "code" and nested.code == "```lua\nx\n```")
check("different fence cannot close block", AST.parseBlocks("~~~\nx\n```")[1].unclosed == true)

print(string.format("== TestMarkdownAST: %d/%d PASS ==", passed, total))
print("ALL-PASS")
print("RUN-DONE")

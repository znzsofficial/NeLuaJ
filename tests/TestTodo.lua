local ASSETS = ASSETS or "app/src/main/assets/"

-- TodoManager 行为测试：纯模块，无外部依赖
package.preload["mods.utils.TextUtil"] = assert(loadfile(ASSETS .. "mods/utils/TextUtil.lua"))
local TM = assert(loadfile(ASSETS .. "mods/agent/TodoManager.lua"))()

local failures = 0
local function check(name, cond)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name)
  end
end

-- 1. 非法输入
local r, ok = TM.update(nil)
check("nil input rejected", ok == false and r:find("必须是任务数组", 1, true))
r, ok = TM.update({ foo = "bar" })
check("object input rejected", ok == false and r:find("不能是对象", 1, true))
r, ok = TM.update({ { status = "pending" } })
check("empty content rejected", ok == false and r:find("content 不能为空", 1, true))

-- 2. 空数组 = 清空计划
r, ok = TM.update({})
check("empty array clears", ok == true and r:find("已清空", 1, true))
TM.commitPending()
check("cleared state is nil", TM.get() == nil and TM.renderForPrompt() == nil)

-- 3. 正常更新 + 提交
r, ok = TM.update({
  { content = "任务A", status = "completed" },
  { content = "任务B", status = "IN_PROGRESS " },
  { content = "任务C" },
})
check("update ok", ok == true and r:find("已完成 1/3", 1, true) ~= nil)
check("state not yet committed", TM.get() == nil)
TM.commitPending()
local got = TM.get()
check("committed 3 items", got and #got == 3)
check("status normalized", got[2].status == "in_progress" and got[3].status == "pending")
check("prompt has plan", TM.renderForPrompt() and TM.renderForPrompt():find("%[已完成%] 任务A", 1))
check("result echoes list", r:find("%[进行中%] 任务B", 1) and r:find("%[待办%] 任务C", 1))

-- 4. commitPending 无 pending 时无操作
TM.commitPending()
check("no-pending commit is noop", TM.get() ~= nil and #TM.get() == 3)

-- 5. 超上限截断
local many = {}
for i = 1, 60 do many[i] = { content = "item" .. i, status = "pending" } end
r, ok = TM.update(many)
check("oversize noted", ok == true and r:find("截断", 1, true) ~= nil)
TM.commitPending()
check("capped at 50", #TM.get() == 50)

-- 6. UTF-8 截断不撕裂多字节字符
local long = string.rep("好", 150) -- 450 字节，截到 200 字节
r, ok = TM.update({ { content = long, status = "pending" } })
TM.commitPending()
local content = TM.get()[1].content
local lastByte = content:byte(#content)
check("utf8 truncate at valid boundary (#content<=200)", #content <= 200)
check("utf8 last byte is not a dangling lead", lastByte < 0xC0)
local good = string.rep("好", math.floor(#content / 3))
check("utf8 content is whole chars", content == good)

-- 7. set 注入 + 非法 set 清空
TM.set({ { content = "x", status = "completed" } })
check("set loads state", TM.get() and TM.get()[1].content == "x")
TM.set({ { content = "y", status = "bogus" } })
check("bogus status coerced", TM.get()[1].status == "pending")
TM.set(nil)
check("set(nil) clears", TM.get() == nil)

-- 8. 被截断的尾部内容仍能渲染（无崩溃）
r, ok = TM.update({ { content = string.rep("ab", 200), status = "pending" } })
check("long ascii truncated ok", ok == true and TM.get() == nil)
TM.commitPending()
check("long ascii committed", TM.get()[1] and #TM.get()[1].content == 200)

if failures == 0 then print("ALL-PASS") else print("FAILURES: " .. failures) end

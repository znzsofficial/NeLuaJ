---@diagnostic disable: undefined-global
return function()
  local Snackbar = bindClass "com.google.android.material.snackbar.Snackbar"
  local TextWatcher = bindClass "android.text.TextWatcher"
  local KeyEvent = bindClass "android.view.KeyEvent"
  local EditorInfo = bindClass "android.view.inputmethod.EditorInfo"
  local JString = bindClass "java.lang.String"
  import "res"

  local VISIBLE, GONE = 0, 8

  local state = {
    keyword = "",
    results = {}, -- { {start, length}, ... } Java char index
    index = 0,
    matchCase = false,
    wholeWord = false,
    replaceOpen = false,
  }

  local function toast(msg)
    Snackbar.make(coordinatorLayout, msg, Snackbar.LENGTH_SHORT)
      .setAnchorView(ps_bar)
      .show()
  end

  local function hasEditor()
    return mLuaEditor and mLuaEditor.getVisibility() ~= 4
  end

  local function isWordChar(c)
    if c == nil or c < 0 then return false end
    return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
  end

  ---@return table
  local function findAll(text, key, matchCase, wholeWord)
    local out = {}
    if text == nil or key == nil then return out end
    local src = tostring(text)
    local needle = tostring(key)
    if needle == "" then return out end
    -- 大文件限制扫描量，避免输入时卡 UI
    local scan = src
    if #scan > 4000000 then
      scan = scan:sub(1, 4000000)
    end
    local jHay = JString(matchCase and scan or scan:lower())
    local jNeedle = JString(matchCase and needle or needle:lower())
    local nlen = jNeedle.length()
    if nlen == 0 then return out end
    local jOrig = JString(scan) -- 全词边界用原始字符
    local from = 0
    local max = jHay.length()
    while from <= max - nlen do
      local idx = jHay.indexOf(jNeedle, from)
      if idx < 0 then break end
      local ok = true
      if wholeWord then
        local before = idx > 0 and jOrig.charAt(idx - 1) or -1
        local after = (idx + nlen < jOrig.length()) and jOrig.charAt(idx + nlen) or -1
        if isWordChar(before) or isWordChar(after) then
          ok = false
        end
      end
      if ok then
        out[#out + 1] = { idx, nlen }
      end
      from = idx + 1
    end
    return out
  end

  local function updateCount()
    if not search_count then return end
    local n = #state.results
    if n == 0 then
      search_count.setText("0/0")
    else
      search_count.setText(tostring(state.index) .. "/" .. tostring(n))
    end
  end

  --- jumpToEditor：仅点上/下一个或替换后跳转；输入时只更新计数，不抢焦点
  local function selectAt(i, jumpToEditor)
    if i < 1 or i > #state.results then return end
    state.index = i
    if jumpToEditor then
      local item = state.results[i]
      pcall(function()
        mLuaEditor.setSelection(item[1], item[2])
      end)
    end
    updateCount()
  end

  --- silent：输入过程中 true，只刷新结果列表/计数
  local function runSearch(keepIndex, silent)
    if not hasEditor() then
      state.results = {}
      state.index = 0
      updateCount()
      return
    end
    local key = tostring(mSearchEdit.getText() or "")
    state.keyword = key
    if key == "" then
      state.results = {}
      state.index = 0
      updateCount()
      return
    end
    state.results = findAll(mLuaEditor.getText(), key, state.matchCase, state.wholeWord)
    local n = #state.results
    if n == 0 then
      state.index = 0
      updateCount()
      return
    end
    local idx = keepIndex and state.index or 1
    if not idx or idx < 1 then idx = 1 end
    if idx > n then idx = n end
    state.index = idx
    if not silent then
      selectAt(idx, true)
    else
      updateCount()
    end
  end

  local function goNext()
    if not hasEditor() then
      toast(res.string.no_file)
      return
    end
    local key = tostring(mSearchEdit.getText() or "")
    if key == "" then
      toast(res.string.search_empty)
      return
    end
    if key ~= state.keyword or #state.results == 0 then
      runSearch(false, false)
      if #state.results == 0 then
        toast(res.string.search_no_result)
      else
        selectAt(state.index, true)
      end
      return
    end
    local n = #state.results
    local next = state.index + 1
    if next > n then next = 1 end
    selectAt(next, true)
  end

  local function goPrev()
    if not hasEditor() then
      toast(res.string.no_file)
      return
    end
    local key = tostring(mSearchEdit.getText() or "")
    if key == "" then
      toast(res.string.search_empty)
      return
    end
    if key ~= state.keyword or #state.results == 0 then
      runSearch(false, false)
      if #state.results == 0 then
        toast(res.string.search_no_result)
      else
        selectAt(state.index, true)
      end
      return
    end
    local n = #state.results
    local prev = state.index - 1
    if prev < 1 then prev = n end
    selectAt(prev, true)
  end

  local function replaceOne()
    if not hasEditor() then
      toast(res.string.no_file)
      return
    end
    if #state.results == 0 or state.index < 1 then
      runSearch(false, true)
      if #state.results == 0 then
        toast(res.string.search_no_result)
        return
      end
      state.index = 1
    end
    local item = state.results[state.index]
    local repl = tostring(mReplaceEdit and mReplaceEdit.getText() or "")
    local jFull = JString(tostring(mLuaEditor.getText()))
    local start = item[1]
    local len = item[2]
    local jRepl = JString(repl)
    local newText = jFull.substring(0, start) .. tostring(jRepl) .. jFull.substring(start + len)
    mLuaEditor.setText(newText)
    mLuaEditor.setSelection(start + jRepl.length())
    runSearch(true, true)
    if #state.results == 0 then toast(res.string.search_no_result) end
  end

  local function replaceAll()
    if not hasEditor() then
      toast(res.string.no_file)
      return
    end
    local key = tostring(mSearchEdit.getText() or "")
    if key == "" then
      toast(res.string.search_empty)
      return
    end
    runSearch(false, true)
    local n = #state.results
    if n == 0 then
      toast(res.string.search_no_result)
      return
    end
    local repl = tostring(mReplaceEdit and mReplaceEdit.getText() or "")
    local jFull = JString(tostring(mLuaEditor.getText()))
    local jRepl = JString(repl)
    for i = n, 1, -1 do
      local item = state.results[i]
      local start = item[1]
      local len = item[2]
      jFull = JString(jFull.substring(0, start) .. tostring(jRepl) .. jFull.substring(start + len))
    end
    mLuaEditor.setText(tostring(jFull))
    state.results = {}
    state.index = 0
    updateCount()
    toast(string.format(res.string.search_replaced_n, n))
  end

  local function setOptStyle(btn, on)
    if not btn then return end
    pcall(function()
      btn.setAlpha(on and 1 or 0.5)
    end)
  end

  local function toggleReplace()
    state.replaceOpen = not state.replaceOpen
    if search_replace_row then
      search_replace_row.setVisibility(state.replaceOpen and VISIBLE or GONE)
    end
    pcall(function()
      if search_toggle_replace then
        search_toggle_replace.setText(
          state.replaceOpen and res.string.search_hide_replace or res.string.replace
        )
      end
    end)
  end

  if search_down then search_down.onClick = goNext end
  if search_up then search_up.onClick = goPrev end
  if search_close then
    search_close.onClick = function()
      pcall(function()
        local Init = package.loaded["activities.main.Init"]
        if Init and Init.Actions and Init.Actions.hideSearchBar then
          Init.Actions.hideSearchBar()
        elseif mSearch then
          mSearch.setVisibility(GONE)
        end
      end)
    end
  end
  if search_clear then
    search_clear.onClick = function()
      mSearchEdit.setText("")
      state.results = {}
      state.index = 0
      state.keyword = ""
      updateCount()
      mSearchEdit.requestFocus()
    end
  end
  if search_replace_one then search_replace_one.onClick = replaceOne end
  if search_replace_all then search_replace_all.onClick = replaceAll end
  if search_toggle_replace then search_toggle_replace.onClick = toggleReplace end

  if search_opt_case then
    setOptStyle(search_opt_case, state.matchCase)
    search_opt_case.onClick = function()
      state.matchCase = not state.matchCase
      setOptStyle(search_opt_case, state.matchCase)
      runSearch(false, true)
    end
  end
  if search_opt_word then
    setOptStyle(search_opt_word, state.wholeWord)
    search_opt_word.onClick = function()
      state.wholeWord = not state.wholeWord
      setOptStyle(search_opt_word, state.wholeWord)
      runSearch(false, true)
    end
  end

  pcall(function()
    mSearchEdit.addTextChangedListener(TextWatcher({
      beforeTextChanged = function() end,
      onTextChanged = function() end,
      afterTextChanged = function()
        -- 输入时只更新匹配数，不跳转编辑器，避免抢焦点
        runSearch(false, true)
      end,
    }))
  end)

  pcall(function()
    mSearchEdit.setOnEditorActionListener(function(v, actionId, event)
      if actionId == EditorInfo.IME_ACTION_SEARCH
        or (event and event.getAction() == KeyEvent.ACTION_DOWN
          and event.getKeyCode() == KeyEvent.KEYCODE_ENTER) then
        goNext()
        return true
      end
      return false
    end)
  end)

  updateCount()
end

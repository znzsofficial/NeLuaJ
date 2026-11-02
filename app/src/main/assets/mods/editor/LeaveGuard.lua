-- Deliberate editor exit only. Lifecycle autosave must never open a dialog.
local M = {}

function M.saved(result)
  return result == true or result == "same"
end

function M.new(options)
  local state, generation = "idle", 0
  local guard = {}
  local function finish()
    state = "leaving"
    options.finish()
    return true
  end

  function guard.save()
    local ok, result = pcall(function()
      local path = options.currentFile()
      if path == nil or path == "" then return "same" end
      return options.save()
    end)
    return ok and M.saved(result), not ok and result or nil
  end

  local attempt
  attempt = function()
    if guard.save() then return finish() end
    state = "prompt"
    generation = generation + 1
    local token = generation
    local captured, snapshot = pcall(options.snapshot)
    local function active() return token == generation and state == "prompt" end
    local function cancel()
      if active() then state = "idle"; generation = generation + 1 end
    end
    options.onFailure({
      retry = function()
        if not active() then return false end
        state = "idle"
        generation = generation + 1
        return attempt()
      end,
      cancel = cancel,
      discard = function()
        if not active() then return false end
        -- A second, explicit destructive confirmation is mandatory.
        state = "confirm"
        options.confirmDiscard(function(confirmed)
          if token ~= generation or state ~= "confirm" then return false end
          state = "idle"
          generation = generation + 1
          if confirmed ~= true then return false end
          -- A delayed confirmation must not discard a newer buffer/file.
          local readable, current = pcall(options.snapshot)
          if not captured or not readable or current ~= snapshot then return attempt() end
          return finish()
        end)
        return false
      end,
    })
    return false
  end

  function guard.request()
    if state ~= "idle" then return false end
    if options.closeTransient and options.closeTransient() then return false end
    return attempt()
  end

  function guard.isLeaving() return state == "leaving" end
  return guard
end

return M

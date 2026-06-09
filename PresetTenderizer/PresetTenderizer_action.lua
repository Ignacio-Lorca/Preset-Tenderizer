-- Shared entry points for Preset Tenderizer action scripts.
local M = {}

local function load_lib()
  local dir = debug.getinfo(3, "S").source:match("^@(.*[\\/])") or ""
  return dofile(dir .. "PresetTenderizer_lib.lua")
end

local function log_errors(errors)
  for _, err in ipairs(errors) do
    reaper.ShowConsoleMsg(err .. "\n")
  end
end

function M.run_load(name, user_id)
  local lib = load_lib()
  local ok, errors = lib.load_and_apply(name, user_id ~= "" and user_id or nil)
  if ok then
    reaper.ShowConsoleMsg("Loaded snapshot: " .. name .. "\n")
  else
    log_errors(errors)
  end
end

function M.run_save_prompt()
  local ok, name = reaper.GetUserInputs("Preset Tenderizer — Save snapshot", 1, "Snapshot name:,extrawidth=240", "")
  if not ok or name == "" then
    return
  end

  local saved, err = load_lib().capture_and_save(name)
  if saved then
    reaper.ShowConsoleMsg("Saved snapshot: " .. name .. "\n")
  else
    reaper.ShowConsoleMsg(tostring(err) .. "\n")
  end
end

return M

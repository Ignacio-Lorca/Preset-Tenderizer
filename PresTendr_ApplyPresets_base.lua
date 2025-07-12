local presets = {
  {track_num = 3, fx_index = 0, preset_name = "1.1"},
  {track_num = 4, fx_index = 0, preset_name = "1.2"},
}

-- Get the folder of the currently running script (assuming you run this inside Reaper)
local info = reaper.get_action_context()
local script_path = info[2]:match("^(.*)[/\\]") or ""

-- Build the full path to the core file inside PresetTenderizer folder
local core_path = script_path .. "\\PresetTenderizer\\preset_changer_core.lua"

-- Load the core script
local status, err = pcall(dofile, core_path)
if not status then
  reaper.ShowConsoleMsg("Failed to load core script: " .. err .. "\n")
  return
end

-- Now you can use functions or code from preset_changer_core.lua
-- For example: preset_changer_core.apply_presets(presets)

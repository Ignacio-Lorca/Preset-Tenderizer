-- Stops the Preset Tenderizer web bridge (running loops exit on the next defer tick).
local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local PT = dofile(dir .. "PresetTenderizer_lib.lua")

PT.stop_web_bridge()

-- reaper.ShowConsoleMsg("Preset Tenderizer web UI bridge stopped.\n")

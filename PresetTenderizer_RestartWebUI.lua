-- Reinstall web files and restart the Preset Tenderizer bridge.
local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""

dofile(dir .. "PresetTenderizer_InstallWebUI.lua")
dofile(dir .. "PresetTenderizer_WebBridge.lua")

reaper.ShowConsoleMsg("Preset Tenderizer web UI restarted. Refresh the browser page.\n")

-- Installs web files and starts the Preset Tenderizer web bridge.
local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
dofile(dir .. "PresetTenderizer_InstallWebUI.lua")
dofile(dir .. "PresetTenderizer_WebBridge.lua")

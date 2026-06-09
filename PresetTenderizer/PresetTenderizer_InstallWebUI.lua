-- Preset Tenderizer — copies web UI files into REAPER's reaper_www_root folder.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local PT = dofile(script_dir .. "PresetTenderizer_lib.lua")

local files = {
  "PresetTenderizer.html",
  "PresetTenderizer.css",
  "PresetTenderizer.js",
}

local source_dir = script_dir .. "www_root/"
local target_dir = PT.get_www_root() .. "/"
reaper.RecursiveCreateDirectory(target_dir, 0)

local copied = 0
for _, name in ipairs(files) do
  local source = source_dir .. name
  local target = target_dir .. name
  local in_file = io.open(source, "rb")
  if not in_file then
    reaper.ShowConsoleMsg("Missing file: " .. source .. "\n")
  else
    local data = in_file:read("*a")
    in_file:close()
    local out_file = io.open(target, "wb")
    if not out_file then
      reaper.ShowConsoleMsg("Could not write: " .. target .. "\n")
    else
      out_file:write(data)
      out_file:close()
      copied = copied + 1
    end
  end
end

reaper.ShowConsoleMsg(string.format("Installed %d web file(s) to:\n%s\n", copied, target_dir))
reaper.ShowConsoleMsg("In REAPER: Preferences > Control/OSC/Web > Add > Web browser interface\n")
reaper.ShowConsoleMsg("Preset Tenderizer: select PresetTenderizer.html and use the Access URL shown there.\n")

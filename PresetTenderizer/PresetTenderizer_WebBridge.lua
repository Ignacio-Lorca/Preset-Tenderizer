-- REAPER bridge for the Preset Tenderizer web UI.
local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local PT = dofile(dir .. "PresetTenderizer_lib.lua")

local bridge_generation = PT.bump_bridge_generation()
local last_command_id = nil
local tick = 0

local function loop()
  if PT.get_bridge_generation() ~= bridge_generation then
    return
  end

  tick = tick + 1

  if tick % 3 == 0 then
    PT.write_web_state()
  end

  local cmd = PT.read_web_command()
  if cmd and cmd.id and cmd.id ~= last_command_id then
    last_command_id = cmd.id
    PT.clear_web_response()
    PT.write_web_response(PT.handle_web_command(cmd))
    PT.write_web_state()
    PT.clear_web_command()
  end

  reaper.defer(loop)
end

PT.prepare_web_bridge()
reaper.defer(loop)

-- Set SNAPSHOT_NAME before assigning this action to OSC / MIDI / Stream Deck.
-- Loads from the project active musician unless MUSICIAN_ID is set below.
local SNAPSHOT_NAME = "My Snapshot"
local MUSICIAN_ID = ""

local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local action = dofile(dir .. "PresetTenderizer_action.lua")

if MUSICIAN_ID ~= "" then
  action.run_load(SNAPSHOT_NAME, MUSICIAN_ID)
else
  action.run_load(SNAPSHOT_NAME)
end

-- Configuration: update these if needed
local fx_index = 0 -- FX slot to read (e.g., 0 = first FX)

local presets = {}

local selected_track_count = reaper.CountSelectedTracks(0)
if selected_track_count == 0 then
  reaper.ShowConsoleMsg("No tracks selected.\n")
else
  for i = 0, selected_track_count - 1 do
    local tr = reaper.GetSelectedTrack(0, i)
    local track_num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") -- 1-based track number
    local retval, preset_name = reaper.TrackFX_GetPreset(tr, fx_index)
    if retval and preset_name ~= "" then
      table.insert(presets, {
        track_num = math.floor(track_num),
        fx_index = fx_index,
        preset_name = preset_name
      })
    else
      reaper.ShowConsoleMsg("Could not read preset from track " .. math.floor(track_num) .. "\n")
    end
  end
end

-- Output to REAPER console as Lua table block
reaper.ShowConsoleMsg("Copy this into your preset script:\n\n")
reaper.ShowConsoleMsg("local presets = {\n")
for _, p in ipairs(presets) do
  reaper.ShowConsoleMsg(string.format("  {track_num = %d; fx_index = %d; preset_name = %q},\n", p.track_num, p.fx_index, p.preset_name))
end
reaper.ShowConsoleMsg("}\n")


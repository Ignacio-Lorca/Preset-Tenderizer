function main(presets)
  reaper.Undo_BeginBlock()

  -- Deselect all tracks
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(tr, false)
  end

  -- Loop through presets and apply each
  for _, info in ipairs(presets) do
    local tr = reaper.GetTrack(0, info.track_num - 1)
    if tr then
      reaper.SetTrackSelected(tr, true)

      local success = reaper.TrackFX_SetPreset(tr, info.fx_index, info.preset_name)
      if success then
        -- Optionally rename track
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", info.preset_name, true)
      else
        reaper.ShowConsoleMsg("⚠️ Failed to set preset '" .. info.preset_name .. "' on track " .. info.track_num .. "\n")
      end
    else
      reaper.ShowConsoleMsg("❌ Track " .. info.track_num .. " not found\n")
    end
  end

  reaper.Undo_EndBlock("Set presets and rename tracks", -1)
end

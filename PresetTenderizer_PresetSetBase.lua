-- Define your presets
local presets = {
  {track_num = 3; fx_index = 0; preset_name = "Clean gtr"},
  {track_num = 4; fx_index = 0; preset_name = "Overdrive gtr"},
  {track_num = 5; fx_index = 0; preset_name = "Distortion Gtr"},
  {track_num = 6; fx_index = 0; preset_name = "Weird Delay"},
  {track_num = 7; fx_index = 0; preset_name = "Song outro"},
}

-- Load and run the core logic
dofile(reaper.GetResourcePath() .. "/Scripts/PresetTenderizer/PresetTenderizer_changer_core.lua")
main(presets)  -- pass the table to the main function

local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
dofile(dir .. "PresetTenderizer_action.lua").run_save_prompt()

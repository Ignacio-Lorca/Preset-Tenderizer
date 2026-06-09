-- Preset Tenderizer — shared capture, restore, and storage logic
local M = {}

local LIB_DIR = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""

M.VERSION = 4
M.EXT_SECTION = "PresetTenderizer"
M.LEGACY_EXT_SECTION = "MonitoringSnapshot"
M.STORAGE_DIR_NAME = "PresetTenderizer"
M.LEGACY_STORAGE_DIR_NAME = "MonitoringSnapshots"
M.STORAGE_FILE = "snapshots.json"
M.USERS_FILE = "users.json"
M.USERS_SUBDIR = "users"
M.DEFAULT_USER_ID = "default"
M.WEB_SECTION = "PresetTenderizerWeb"
M.LEGACY_WEB_SECTION = "MonitoringSnapshotWeb"

local SEND_PARAMS = {
  "B_MUTE",
  "B_PHASE",
  "B_MONO",
  "D_VOL",
  "D_PAN",
  "D_PANLAW",
  "I_SENDMODE",
  "I_SRCCHAN",
  "I_DSTCHAN",
  "I_MIDIFLAGS",
  "I_AUTOMODE",
}

function M.get_track_name(tr)
  if not tr then
    return ""
  end
  local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name or ""
end

function M.get_track_guid(tr)
  if not tr then
    return ""
  end
  return reaper.GetTrackGUID(tr)
end

function M.find_track_by_guid(guid)
  if not guid or guid == "" then
    return nil
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then
      return tr
    end
  end

  return nil
end

function M.list_project_tracks()
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    table.insert(tracks, {
      track = tr,
      guid = M.get_track_guid(tr),
      name = M.get_track_name(tr),
      index = i + 1,
    })
  end
  return tracks
end

function M.classify_project_tracks()
  local classified = {}
  local depth = 0

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local folder_depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local inside_folder = depth > 0
    local is_folder = folder_depth > 0

    table.insert(classified, {
      track = tr,
      guid = M.get_track_guid(tr),
      name = M.get_track_name(tr),
      index = i + 1,
      is_folder = is_folder,
      inside_folder = inside_folder,
    })

    depth = depth + folder_depth
  end

  return classified
end

function M.track_entry_for_web(entry)
  return {
    guid = entry.guid,
    name = M.normalize_web_string(entry.name),
    index = entry.index,
  }
end

function M.list_folder_tracks()
  local tracks = {}

  for _, entry in ipairs(M.classify_project_tracks()) do
    if entry.is_folder then
      table.insert(tracks, entry)
    end
  end

  return tracks
end

function M.list_monitor_candidate_tracks()
  local tracks = {}

  for _, entry in ipairs(M.classify_project_tracks()) do
    if not entry.inside_folder then
      table.insert(tracks, entry)
    end
  end

  return tracks
end

function M.extract_fx_chain_chunk(track_chunk)
  if not track_chunk or track_chunk == "" then
    return nil
  end

  local fx_start = track_chunk:find("<FXCHAIN", 1, true)
  if not fx_start then
    return nil
  end

  local depth = 0
  local i = fx_start
  local len = #track_chunk

  while i <= len do
    local ch = track_chunk:sub(i, i)
    if ch == "<" then
      depth = depth + 1
    elseif ch == ">" then
      depth = depth - 1
      if depth == 0 then
        return track_chunk:sub(fx_start, i)
      end
    end
    i = i + 1
  end

  return nil
end

function M.get_tracks_in_folder(folder_tr)
  local tracks = {}
  if not folder_tr then
    return tracks
  end

  local start_idx = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    if reaper.GetTrack(0, i) == folder_tr then
      start_idx = i
      break
    end
  end

  if start_idx == nil then
    return tracks
  end

  local depth = reaper.GetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH")
  if depth <= 0 then
    return tracks
  end

  for i = start_idx + 1, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    table.insert(tracks, tr)
    depth = depth + reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if depth <= 0 then
      break
    end
  end

  return tracks
end

function M.set_track_name(tr, name)
  if not tr then
    return
  end
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name or "", true)
end

function M.apply_track_name_for_fx(tr, track_data)
  if not tr then
    return
  end

  if reaper.TrackFX_GetCount(tr) < 1 then
    M.set_track_name(tr, "")
    return
  end

  local preset_name = M.resolve_track_preset_name(tr, track_data)
  if preset_name ~= "" then
    M.set_track_name(tr, preset_name)
  end
end

local GENERIC_PRESET_NAMES = {
  Default = true,
  ["(default)"] = true,
  ["(Default)"] = true,
}

local function is_generic_preset_name(name)
  if not name or name == "" then
    return true
  end
  return GENERIC_PRESET_NAMES[name] == true
end

function M.is_fx_container(tr, fx_idx)
  return reaper.TrackFX_GetIOSize(tr, fx_idx) == 8
end

function M.container_child_fx_index(tr, container_idx, child_idx)
  local n = reaper.TrackFX_GetCount(tr)
  return 0x2000000 + (container_idx + 1) * (n + 1) + (child_idx + 1)
end

local function read_preset_at(tr, fx_idx)
  local ok, preset_name = reaper.TrackFX_GetPreset(tr, fx_idx)
  if ok and preset_name and preset_name ~= "" then
    return preset_name
  end
  return nil
end

local function collect_track_preset_candidates(tr)
  local candidates = {}
  local fx_count = reaper.TrackFX_GetCount(tr)
  if fx_count < 1 then
    return candidates
  end

  for fx_idx = fx_count - 1, 0, -1 do
    if M.is_fx_container(tr, fx_idx) then
      local ok, count_str = reaper.TrackFX_GetNamedConfigParm(tr, fx_idx, "container_count")
      local child_count = ok and tonumber(count_str) or 0
      for child_idx = child_count - 1, 0, -1 do
        local name = read_preset_at(tr, M.container_child_fx_index(tr, fx_idx, child_idx))
        if name then
          table.insert(candidates, name)
        end
      end
    else
      local name = read_preset_at(tr, fx_idx)
      if name then
        table.insert(candidates, name)
      end
    end
  end

  return candidates
end

function M.preset_from_fx_chain(fx_chain)
  if not fx_chain or fx_chain == "" then
    return ""
  end

  local best = ""
  local best_generic = ""
  for line in fx_chain:gmatch("[^\r\n]+") do
    local name = line:match('^PRESETNAME%s+"(.-)"') or line:match("^PRESETNAME%s+(%S+)")
    if name then
      if is_generic_preset_name(name) then
        if best_generic == "" then
          best_generic = name
        end
      else
        best = name
      end
    end
  end

  if best ~= "" then
    return best
  end
  return best_generic
end

function M.resolve_track_preset_name(tr, track_data)
  if track_data and track_data.preset_name and track_data.preset_name ~= "" then
    return track_data.preset_name
  end

  if tr then
    local live = M.get_fx_preset_name(tr)
    if live ~= "" then
      return live
    end
  end

  if track_data and track_data.fx_chain then
    return M.preset_from_fx_chain(track_data.fx_chain)
  end

  return ""
end

function M.get_fx_preset_name(tr)
  if not tr or reaper.TrackFX_GetCount(tr) < 1 then
    return ""
  end

  local candidates = collect_track_preset_candidates(tr)
  for _, name in ipairs(candidates) do
    if not is_generic_preset_name(name) then
      return name
    end
  end

  return candidates[1] or ""
end

function M.list_folder_child_tracks(folder_tr)
  local tracks = {}
  if not folder_tr then
    return tracks
  end

  for _, child_tr in ipairs(M.get_tracks_in_folder(folder_tr)) do
    table.insert(tracks, {
      name = M.normalize_web_string(M.get_track_name(child_tr)),
      muted = reaper.GetMediaTrackInfo_Value(child_tr, "B_MUTE") ~= 0,
    })
  end

  return tracks
end

function M.capture_track_fx(tr)
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok or not chunk then
    return nil
  end

  local fx_chain = M.extract_fx_chain_chunk(chunk) or ""
  local fx_count = reaper.TrackFX_GetCount(tr)
  local preset_name = ""

  if fx_count < 1 then
    M.set_track_name(tr, "")
  else
    preset_name = M.get_fx_preset_name(tr)
    if fx_chain == "" then
      reaper.ShowConsoleMsg(
        "Warning: could not capture FX chain on track '" .. M.get_track_name(tr) .. "'.\n"
      )
    end
    if preset_name ~= "" then
      M.set_track_name(tr, preset_name)
    end
  end

  return {
    guid = M.get_track_guid(tr),
    name = M.get_track_name(tr),
    preset_name = preset_name,
    fx_enabled = reaper.GetMediaTrackInfo_Value(tr, "I_FXEN") ~= 0,
    fx_chain = fx_chain,
  }
end

function M.capture_folder_fx_tracks(folder_tr, parent_role)
  local tracks = {}
  if not folder_tr then
    return tracks
  end

  local folder_guid = M.get_track_guid(folder_tr)
  local folder_name = M.get_track_name(folder_tr)

  for _, child_tr in ipairs(M.get_tracks_in_folder(folder_tr)) do
    local track_data = M.capture_track_fx(child_tr)
    if track_data then
      track_data.parent_guid = folder_guid
      track_data.parent_name = folder_name
      track_data.parent_role = parent_role
      table.insert(tracks, track_data)
    end
  end

  return tracks
end

function M.find_receive_index_for_source(monitor_tr, src_tr)
  local recv_count = reaper.GetTrackNumSends(monitor_tr, -1)
  for recv_idx = 0, recv_count - 1 do
    local ok, src = pcall(function()
      return reaper.GetTrackSendInfo_Value(monitor_tr, -1, recv_idx, "P_SRCTRACK")
    end)
    if ok and src == src_tr then
      return recv_idx
    end
  end

  local match_idx = 0
  for i = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, i)
    local send_count = reaper.GetTrackNumSends(candidate, 0)
    for send_idx = 0, send_count - 1 do
      local dest = reaper.GetTrackSendInfo_Value(candidate, 0, send_idx, "P_DESTTRACK")
      if dest == monitor_tr then
        if candidate == src_tr then
          return match_idx
        end
        match_idx = match_idx + 1
      end
    end
  end

  return nil
end

function M.capture_receive_from_source(monitor_tr, src_tr)
  local recv_idx = M.find_receive_index_for_source(monitor_tr, src_tr)
  if recv_idx == nil then
    return nil
  end

  local receive = {
    source_guid = M.get_track_guid(src_tr),
    source_name = M.get_track_name(src_tr),
  }

  for _, param in ipairs(SEND_PARAMS) do
    receive[param] = reaper.GetTrackSendInfo_Value(monitor_tr, -1, recv_idx, param)
  end

  return receive
end

function M.capture_monitor_receives_from_sources(monitor_tr, source_tracks)
  local receives = {}

  for _, src_tr in ipairs(source_tracks) do
    if src_tr then
      local receive = M.capture_receive_from_source(monitor_tr, src_tr)
      if receive then
        table.insert(receives, receive)
      end
    end
  end

  return receives
end

function M.capture_snapshot(vocal_tr, instrument_tr, monitor_tr)
  if not monitor_tr then
    return nil, "Monitor track is not set."
  end
  if not vocal_tr and not instrument_tr then
    return nil, "Set at least one of vocal or instrument track."
  end

  local tracks = {}
  local source_tracks = {}

  if vocal_tr then
    for _, track_data in ipairs(M.capture_folder_fx_tracks(vocal_tr, "vocal")) do
      table.insert(tracks, track_data)
    end
    table.insert(source_tracks, vocal_tr)
  end

  if instrument_tr then
    for _, track_data in ipairs(M.capture_folder_fx_tracks(instrument_tr, "instrument")) do
      table.insert(tracks, track_data)
    end
    table.insert(source_tracks, instrument_tr)
  end

  for _, track_data in ipairs(tracks) do
    local captured_tr = M.find_track_by_guid(track_data.guid)
    if track_data.fx_chain == "" and captured_tr and reaper.TrackFX_GetCount(captured_tr) > 0 then
      return nil, "FX capture failed on track '" .. track_data.name .. "'."
    end
  end

  local receives = M.capture_monitor_receives_from_sources(monitor_tr, source_tracks)
  if #tracks == 0 and #receives == 0 then
    return nil, "Nothing to capture: no FX tracks inside folders and no monitor receives."
  end

  local snapshot = {
    version = M.VERSION,
    created = os.time(),
    vocal_track_guid = vocal_tr and M.get_track_guid(vocal_tr) or nil,
    vocal_track_name = vocal_tr and M.get_track_name(vocal_tr) or nil,
    instrument_track_guid = instrument_tr and M.get_track_guid(instrument_tr) or nil,
    instrument_track_name = instrument_tr and M.get_track_name(instrument_tr) or nil,
    monitor_track_guid = M.get_track_guid(monitor_tr),
    monitor_track_name = M.get_track_name(monitor_tr),
    tracks = tracks,
    receives = receives,
  }

  return snapshot, nil
end

function M.insert_fx_chain_after_mainsend(track_chunk, fx_chain_chunk)
  local mainsend_end = select(2, track_chunk:find("MAINSEND.-\n"))
  if not mainsend_end then
    return track_chunk .. "\n" .. fx_chain_chunk .. "\n"
  end

  return track_chunk:sub(1, mainsend_end) .. fx_chain_chunk .. "\n" .. track_chunk:sub(mainsend_end + 1)
end

function M.replace_fx_chain_in_chunk(track_chunk, fx_chain_chunk)
  if not track_chunk or track_chunk == "" then
    return nil
  end

  local existing = M.extract_fx_chain_chunk(track_chunk)

  if not fx_chain_chunk or fx_chain_chunk == "" then
    if not existing then
      return track_chunk
    end
    local start = track_chunk:find(existing, 1, true)
    if not start then
      return track_chunk
    end
    return track_chunk:sub(1, start - 1) .. track_chunk:sub(start + #existing)
  end

  if existing then
    local start = track_chunk:find(existing, 1, true)
    if start then
      return track_chunk:sub(1, start - 1) .. fx_chain_chunk .. track_chunk:sub(start + #existing)
    end
  end

  return M.insert_fx_chain_after_mainsend(track_chunk, fx_chain_chunk)
end

function M.restore_track_fx(track_data)
  local tr = M.find_track_by_guid(track_data.guid)
  if not tr then
    return false, "Track not found: " .. (track_data.name or track_data.guid)
  end

  if not track_data.fx_chain or track_data.fx_chain == "" then
    local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if ok and chunk then
      local new_chunk = M.replace_fx_chain_in_chunk(chunk, "")
      if new_chunk then
        reaper.SetTrackStateChunk(tr, new_chunk, false)
      end
    end
    reaper.SetMediaTrackInfo_Value(tr, "I_FXEN", track_data.fx_enabled and 1 or 0)
    M.apply_track_name_for_fx(tr, track_data)
    return true
  end

  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if not ok or not chunk then
    return false, "Could not read track state for " .. (track_data.name or track_data.guid)
  end

  local new_chunk = M.replace_fx_chain_in_chunk(chunk, track_data.fx_chain)
  if not new_chunk then
    return false, "Could not build FX state for " .. (track_data.name or track_data.guid)
  end

  if not reaper.SetTrackStateChunk(tr, new_chunk, false) then
    return false, "Failed to apply FX chain on " .. (track_data.name or track_data.guid)
  end

  reaper.SetMediaTrackInfo_Value(tr, "I_FXEN", track_data.fx_enabled and 1 or 0)
  M.apply_track_name_for_fx(tr, track_data)

  return true
end

function M.set_receive_params(monitor_tr, recv_idx, receive)
  for _, param in ipairs(SEND_PARAMS) do
    if receive[param] ~= nil then
      reaper.SetTrackSendInfo_Value(monitor_tr, -1, recv_idx, param, receive[param])
    end
  end
end

function M.restore_monitor_receives(monitor_tr, receives)
  local errors = {}
  local desired = {}

  for _, receive in ipairs(receives) do
    desired[receive.source_guid] = receive
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local src_tr = reaper.GetTrack(0, i)
    local guid = M.get_track_guid(src_tr)
    local send_count = reaper.GetTrackNumSends(src_tr, 0)
    for send_idx = send_count - 1, 0, -1 do
      local dest = reaper.GetTrackSendInfo_Value(src_tr, 0, send_idx, "P_DESTTRACK")
      if dest == monitor_tr and not desired[guid] then
        reaper.RemoveTrackSend(src_tr, 0, send_idx)
      end
    end
  end

  for _, receive in ipairs(receives) do
    local src_tr = M.find_track_by_guid(receive.source_guid)
    if not src_tr then
      table.insert(errors, "Receive source not found: " .. (receive.source_name or receive.source_guid))
    else
      local has_send = false
      local send_count = reaper.GetTrackNumSends(src_tr, 0)
      for send_idx = 0, send_count - 1 do
        local dest = reaper.GetTrackSendInfo_Value(src_tr, 0, send_idx, "P_DESTTRACK")
        if dest == monitor_tr then
          has_send = true
          break
        end
      end

      if not has_send then
        local new_send = reaper.CreateTrackSend(src_tr, monitor_tr)
        if new_send < 0 then
          table.insert(errors, "Failed to create receive from " .. (receive.source_name or receive.source_guid))
        end
      end

      local recv_idx = M.find_receive_index_for_source(monitor_tr, src_tr)
      if recv_idx ~= nil then
        M.set_receive_params(monitor_tr, recv_idx, receive)
      else
        table.insert(errors, "Could not resolve receive for " .. (receive.source_name or receive.source_guid))
      end
    end
  end

  return errors
end

function M.restore_snapshot(snapshot, opts)
  opts = opts or {}
  local errors = {}

  if not snapshot then
    return { "Snapshot is empty." }
  end

  local monitor_tr = M.find_track_by_guid(snapshot.monitor_track_guid)
  if not monitor_tr then
    table.insert(errors, "Monitor track not found: " .. (snapshot.monitor_track_name or snapshot.monitor_track_guid))
    return errors
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for _, track_data in ipairs(snapshot.tracks or {}) do
    local ok, err = M.restore_track_fx(track_data)
    if not ok then
      table.insert(errors, err)
    end
  end

  local recv_errors = M.restore_monitor_receives(monitor_tr, snapshot.receives or {})
  for _, err in ipairs(recv_errors) do
    table.insert(errors, err)
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Preset Tenderizer: restore", -1)
  reaper.UpdateArrange()

  return errors
end

function M.get_json()
  if not M._json then
    M._json = dofile(LIB_DIR .. "PresetTenderizer_json.lua")
  end
  return M._json
end

function M.normalize_web_string(s)
  if s == nil then
    return ""
  end
  return tostring(s):gsub("\\", "/"):gsub("[\r\n\t]", " ")
end

function M.get_base_storage_dir()
  local proj_path = reaper.GetProjectPath("")
  if proj_path ~= "" then
    return M.normalize_web_string(proj_path .. "/" .. M.STORAGE_DIR_NAME)
  end

  local _, proj_name = reaper.GetProjectName(0, "")
  local resource = reaper.GetResourcePath()
  local safe_name = (proj_name ~= "" and proj_name or "Untitled"):gsub("[\\/:*?\"<>|]", "_")
  return M.normalize_web_string(resource .. "/" .. M.STORAGE_DIR_NAME .. "/" .. safe_name)
end

function M.build_storage_path(storage_dir, file_name)
  file_name = file_name or M.STORAGE_FILE
  local proj_path = reaper.GetProjectPath("")
  local _, proj_name = reaper.GetProjectName(0, "")

  if proj_path ~= "" then
    return M.normalize_web_string(proj_path .. "/" .. storage_dir .. "/" .. file_name)
  end

  local resource = reaper.GetResourcePath()
  local safe_name = (proj_name ~= "" and proj_name or "Untitled"):gsub("[\\/:*?\"<>|]", "_")
  return M.normalize_web_string(resource .. "/" .. storage_dir .. "/" .. safe_name .. ".json")
end

function M.get_users_registry_path()
  return M.get_base_storage_dir() .. "/" .. M.USERS_FILE
end

function M.get_user_snapshots_path(user_id)
  return M.get_base_storage_dir() .. "/" .. M.USERS_SUBDIR .. "/" .. user_id .. "/" .. M.STORAGE_FILE
end

function M.get_storage_path(user_id)
  user_id = user_id or M.get_active_user_id()
  return M.get_user_snapshots_path(user_id)
end

function M.get_legacy_flat_storage_paths()
  return {
    M.build_storage_path(M.STORAGE_DIR_NAME),
    M.build_storage_path(M.LEGACY_STORAGE_DIR_NAME),
  }
end

function M.get_legacy_storage_path()
  return M.build_storage_path(M.STORAGE_DIR_NAME):gsub("%.json$", ".lua")
end

function M.get_www_root()
  local resource = reaper.GetResourcePath()
  local primary = resource .. "/reaper_www_root"
  local alternate = resource .. "/Plugins/reaper_www_root"
  if reaper.file_exists(alternate) and not reaper.file_exists(primary) then
    return alternate
  end
  return primary
end

function M.ensure_storage_dir(path)
  local dir = path:match("^(.*)[\\/][^\\/]+$")
  if not dir or dir == "" then
    return
  end
  reaper.RecursiveCreateDirectory(dir, 0)
end

function M.empty_store()
  return {
    version = M.VERSION,
    snapshots = {},
    slots = {},
  }
end

function M.load_store_from_lua(path)
  local chunk = loadfile(path)
  if not chunk then
    return nil
  end
  local ok, store = pcall(chunk)
  if not ok or type(store) ~= "table" then
    return nil
  end
  store.snapshots = store.snapshots or {}
  store.slots = store.slots or {}
  return store
end

function M.save_user_store(user_id, store)
  local path = M.get_user_snapshots_path(user_id)
  M.ensure_storage_dir(path)

  local json = M.get_json()
  if not json.write_file(path, store) then
    return false, "Could not write snapshot store: " .. path
  end
  return true, path
end

function M.load_legacy_flat_store()
  local json = M.get_json()
  local store

  for _, legacy_path in ipairs(M.get_legacy_flat_storage_paths()) do
    store = json.read_file(legacy_path)
    if store then
      return store
    end
  end

  store = M.load_store_from_lua(M.get_legacy_storage_path())
  if store then
    return store
  end

  for _, legacy_path in ipairs(M.get_legacy_flat_storage_paths()) do
    store = M.load_store_from_lua(legacy_path:gsub("%.json$", ".lua"))
    if store then
      return store
    end
  end

  return nil
end

function M.load_user_store(user_id)
  local path = M.get_user_snapshots_path(user_id)
  local json = M.get_json()
  local store = json.read_file(path)

  if not store then
    return M.empty_store(), path
  end

  store.snapshots = store.snapshots or {}
  store.slots = store.slots or {}
  return store, path
end

function M.save_store(store, user_id)
  return M.save_user_store(user_id or M.get_active_user_id(), store)
end

function M.load_store(user_id)
  M.ensure_users_migrated()
  return M.load_user_store(user_id or M.get_active_user_id())
end

function M.count_user_snapshots(user_id)
  local store = select(1, M.load_user_store(user_id))
  local count = 0
  for _ in pairs(store.snapshots or {}) do
    count = count + 1
  end
  return count
end

local function get_ext_value(section, key)
  local _, value = reaper.GetProjExtState(0, section, key)
  if value ~= "" then
    return value
  end
  return nil
end

function M.user_config_key(user_id, field)
  return "user:" .. user_id .. ":" .. field
end

function M.get_user_config(user_id)
  user_id = user_id or M.get_active_user_id()
  M.ensure_users_migrated()

  local vocal_key = M.user_config_key(user_id, "vocal_guid")
  local instrument_key = M.user_config_key(user_id, "instrument_guid")
  local monitor_key = M.user_config_key(user_id, "monitor_guid")

  local vocal_guid = get_ext_value(M.EXT_SECTION, vocal_key)
  local instrument_guid = get_ext_value(M.EXT_SECTION, instrument_key)
  local monitor_guid = get_ext_value(M.EXT_SECTION, monitor_key)

  if user_id == M.DEFAULT_USER_ID then
    vocal_guid = vocal_guid
      or get_ext_value(M.EXT_SECTION, "vocal_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "vocal_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "folder_guid")
    instrument_guid = instrument_guid
      or get_ext_value(M.EXT_SECTION, "instrument_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "instrument_guid")
    monitor_guid = monitor_guid
      or get_ext_value(M.EXT_SECTION, "monitor_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "monitor_guid")
  end

  return {
    vocal_guid = vocal_guid,
    instrument_guid = instrument_guid,
    monitor_guid = monitor_guid,
  }
end

function M.set_user_config(user_id, vocal_guid, instrument_guid, monitor_guid)
  user_id = user_id or M.get_active_user_id()
  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "vocal_guid"), vocal_guid or "")
  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "instrument_guid"), instrument_guid or "")
  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "monitor_guid"), monitor_guid or "")
end

function M.get_config(user_id)
  return M.get_user_config(user_id)
end

function M.set_config(vocal_guid, instrument_guid, monitor_guid, user_id)
  M.set_user_config(user_id, vocal_guid, instrument_guid, monitor_guid)
end

function M.get_config_tracks(user_id)
  local config = M.get_user_config(user_id)
  return {
    vocal_tr = M.find_track_by_guid(config.vocal_guid),
    instrument_tr = M.find_track_by_guid(config.instrument_guid),
    monitor_tr = M.find_track_by_guid(config.monitor_guid),
    vocal_guid = config.vocal_guid,
    instrument_guid = config.instrument_guid,
    monitor_guid = config.monitor_guid,
  }
end

function M.slugify_user_id(display_name)
  local slug = tostring(display_name or ""):lower()
  slug = slug:gsub("[^%w]+", "_")
  slug = slug:gsub("^_+", ""):gsub("_+$", "")
  if slug == "" then
    slug = "musician"
  end
  return slug
end

function M.unique_user_id(display_name, registry)
  local base = M.slugify_user_id(display_name)
  local candidate = base
  local suffix = 2

  while M.find_user(registry, candidate) do
    candidate = base .. "_" .. tostring(suffix)
    suffix = suffix + 1
  end

  return candidate
end

function M.find_user(registry, user_id)
  for _, user in ipairs(registry.users or {}) do
    if user.id == user_id then
      return user
    end
  end
  return nil
end

function M.load_users_registry()
  M.ensure_storage_dir(M.get_users_registry_path())
  local json = M.get_json()
  local registry = json.read_file(M.get_users_registry_path())
  if not registry or type(registry.users) ~= "table" then
    return {
      version = 1,
      users = {},
    }
  end
  return registry
end

function M.save_users_registry(registry)
  M.ensure_storage_dir(M.get_users_registry_path())
  local json = M.get_json()
  return json.write_file(M.get_users_registry_path(), registry)
end

function M.list_users()
  M.ensure_users_migrated()
  local registry = M.load_users_registry()
  table.sort(registry.users, function(a, b)
    return (a.display_name or a.id):lower() < (b.display_name or b.id):lower()
  end)
  return registry.users
end

function M.get_active_user_id()
  M.ensure_users_migrated()
  local active = get_ext_value(M.EXT_SECTION, "active_user_id")
  if active and M.find_user(M.load_users_registry(), active) then
    return active
  end

  local users = M.list_users()
  if users[1] then
    M.set_active_user_id(users[1].id)
    return users[1].id
  end

  return M.DEFAULT_USER_ID
end

function M.set_active_user_id(user_id)
  if not M.find_user(M.load_users_registry(), user_id) then
    return false, "Musician not found: " .. tostring(user_id)
  end
  reaper.SetProjExtState(0, M.EXT_SECTION, "active_user_id", user_id)
  return true
end

function M.migrate_legacy_config_to_user(user_id)
  local config = {
    vocal_guid = get_ext_value(M.EXT_SECTION, "vocal_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "vocal_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "folder_guid"),
    instrument_guid = get_ext_value(M.EXT_SECTION, "instrument_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "instrument_guid"),
    monitor_guid = get_ext_value(M.EXT_SECTION, "monitor_guid")
      or get_ext_value(M.LEGACY_EXT_SECTION, "monitor_guid"),
  }

  if config.vocal_guid or config.instrument_guid or config.monitor_guid then
    M.set_user_config(user_id, config.vocal_guid, config.instrument_guid, config.monitor_guid)
  end
end

function M.ensure_users_migrated()
  if M._users_migrated then
    return
  end

  M.ensure_storage_dir(M.get_users_registry_path())
  local registry = M.load_users_registry()

  if #(registry.users or {}) == 0 then
    local legacy_store = M.load_legacy_flat_store()
    table.insert(registry.users, {
      id = M.DEFAULT_USER_ID,
      display_name = "Default",
      created = os.time(),
    })
    M.save_users_registry(registry)

    if legacy_store then
      M.save_user_store(M.DEFAULT_USER_ID, legacy_store)
    else
      M.save_user_store(M.DEFAULT_USER_ID, M.empty_store())
    end

    M.migrate_legacy_config_to_user(M.DEFAULT_USER_ID)
    M.set_active_user_id(M.DEFAULT_USER_ID)
  end

  M._users_migrated = true
end

function M.create_user(display_name)
  display_name = (display_name or ""):match("^%s*(.-)%s*$")
  if display_name == "" then
    return false, "Musician name is required."
  end

  M.ensure_users_migrated()
  local registry = M.load_users_registry()
  local user_id = M.unique_user_id(display_name, registry)

  table.insert(registry.users, {
    id = user_id,
    display_name = display_name,
    created = os.time(),
  })

  if not M.save_users_registry(registry) then
    return false, "Could not save musician registry."
  end

  M.save_user_store(user_id, M.empty_store())
  return true, user_id
end

function M.rename_user(user_id, display_name)
  display_name = (display_name or ""):match("^%s*(.-)%s*$")
  if not user_id or user_id == "" or display_name == "" then
    return false, "Musician id and name are required."
  end

  M.ensure_users_migrated()
  local registry = M.load_users_registry()
  local user = M.find_user(registry, user_id)
  if not user then
    return false, "Musician not found: " .. user_id
  end

  user.display_name = display_name
  if not M.save_users_registry(registry) then
    return false, "Could not save musician registry."
  end

  return true
end

function M.delete_user(user_id)
  M.ensure_users_migrated()
  local registry = M.load_users_registry()

  if #(registry.users or {}) <= 1 then
    return false, "Cannot delete the last musician."
  end

  local found = false
  local next_users = {}
  for _, user in ipairs(registry.users) do
    if user.id == user_id then
      found = true
    else
      table.insert(next_users, user)
    end
  end

  if not found then
    return false, "Musician not found: " .. user_id
  end

  registry.users = next_users
  if not M.save_users_registry(registry) then
    return false, "Could not save musician registry."
  end

  local snapshot_path = M.get_user_snapshots_path(user_id)
  os.remove(snapshot_path)

  if M.get_active_user_id() == user_id then
    M.set_active_user_id(next_users[1].id)
  end

  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "vocal_guid"), "")
  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "instrument_guid"), "")
  reaper.SetProjExtState(0, M.EXT_SECTION, M.user_config_key(user_id, "monitor_guid"), "")

  return true
end

function M.list_snapshot_names(store)
  local names = {}
  for name in pairs(store.snapshots) do
    table.insert(names, name)
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function M.save_named_snapshot(name, snapshot, user_id)
  if not name or name == "" then
    return false, "Snapshot name is required."
  end

  local store = M.load_store(user_id)
  store.snapshots[name] = snapshot
  return M.save_store(store, user_id)
end

function M.delete_named_snapshot(name, user_id)
  local store = M.load_store(user_id)
  if not store.snapshots[name] then
    return false, "Snapshot not found: " .. name
  end

  store.snapshots[name] = nil

  for slot, slot_name in pairs(store.slots) do
    if slot_name == name then
      store.slots[slot] = nil
    end
  end

  return M.save_store(store, user_id)
end

function M.load_named_snapshot(name, user_id)
  local store = select(1, M.load_user_store(user_id or M.get_active_user_id()))
  return store.snapshots[name], store
end

function M.capture_and_save(name, user_id)
  local tracks = M.get_config_tracks(user_id)
  if not tracks.monitor_tr then
    return false, "Set monitor track before saving."
  end
  if not tracks.vocal_tr and not tracks.instrument_tr then
    return false, "Set vocal and/or instrument track before saving."
  end

  local snapshot, err = M.capture_snapshot(tracks.vocal_tr, tracks.instrument_tr, tracks.monitor_tr)
  if not snapshot then
    return false, err
  end

  return M.save_named_snapshot(name, snapshot, user_id)
end

function M.load_and_apply(name, user_id)
  local snapshot = M.load_named_snapshot(name, user_id)
  if not snapshot then
    return false, { "Snapshot not found: " .. name }
  end

  local errors = M.restore_snapshot(snapshot)
  if #errors > 0 then
    return false, errors
  end

  return true, nil
end

function M.rename_snapshot(old_name, new_name, user_id)
  if not old_name or old_name == "" or not new_name or new_name == "" then
    return false, "Both names are required."
  end
  if old_name == new_name then
    return true
  end

  local store = M.load_store(user_id)
  if not store.snapshots[old_name] then
    return false, "Snapshot not found: " .. old_name
  end
  if store.snapshots[new_name] then
    return false, "Name already exists: " .. new_name
  end

  store.snapshots[new_name] = store.snapshots[old_name]
  store.snapshots[old_name] = nil

  for slot, slot_name in pairs(store.slots) do
    if slot_name == old_name then
      store.slots[slot] = new_name
    end
  end

  return M.save_store(store, user_id)
end

function M.snapshot_summary(name, snapshot)
  local vocal_fx_count = 0
  local instrument_fx_count = 0

  for _, track in ipairs(snapshot.tracks or {}) do
    if track.parent_role == "vocal" then
      vocal_fx_count = vocal_fx_count + 1
    elseif track.parent_role == "instrument" then
      instrument_fx_count = instrument_fx_count + 1
    end
  end

  return {
    name = name,
    created = snapshot.created,
    track_count = #(snapshot.tracks or {}),
    vocal_fx_count = vocal_fx_count,
    instrument_fx_count = instrument_fx_count,
    receive_count = #(snapshot.receives or {}),
    vocal_track_name = snapshot.vocal_track_name,
    instrument_track_name = snapshot.instrument_track_name,
    monitor_track_name = snapshot.monitor_track_name,
  }
end

local function summarize_fx_chain(chain, max_chars)
  if not chain or chain == "" then
    return "", 0, false
  end

  local len = #chain
  if max_chars <= 0 then
    return "", len, len > 0
  end
  if len <= max_chars then
    return chain, len, false
  end

  return chain:sub(1, max_chars) .. "\n... (" .. (len - max_chars) .. " more bytes)", len, true
end

function M.snapshot_for_debug(snapshot, opts)
  opts = opts or {}
  local max_fx_chars = opts.max_fx_chars or 1500
  local out = {}

  for key, value in pairs(snapshot) do
    if key ~= "tracks" then
      out[key] = value
    end
  end

  out.tracks = {}
  for _, track in ipairs(snapshot.tracks or {}) do
    local chain, len, truncated = summarize_fx_chain(track.fx_chain, max_fx_chars)
    table.insert(out.tracks, {
      name = track.name,
      guid = track.guid,
      preset_name = track.preset_name,
      parent_guid = track.parent_guid,
      parent_name = track.parent_name,
      parent_role = track.parent_role,
      fx_enabled = track.fx_enabled,
      fx_chain_byte_length = len,
      fx_chain_truncated = truncated,
      fx_chain = chain,
    })
  end

  return out
end

function M.get_named_snapshot(name, user_id)
  if not name or name == "" then
    return nil, "Snapshot name is required."
  end

  local store = M.load_store(user_id)
  local snapshot = store.snapshots[name]
  if not snapshot then
    return nil, "Snapshot not found: " .. name
  end

  return snapshot
end

function M.build_web_state()
  local _, proj_name = reaper.GetProjectName(0, "")

  local users = {}
  for _, user in ipairs(M.list_users()) do
    table.insert(users, {
      id = user.id,
      display_name = M.normalize_web_string(user.display_name or user.id),
      snapshot_count = M.count_user_snapshots(user.id),
    })
  end

  local tracks = {}
  local folder_tracks = {}
  local monitor_tracks = {}
  for _, entry in ipairs(M.classify_project_tracks()) do
    local web_entry = M.track_entry_for_web(entry)
    table.insert(tracks, web_entry)
    if entry.is_folder then
      table.insert(folder_tracks, web_entry)
    end
    if not entry.inside_folder then
      table.insert(monitor_tracks, web_entry)
    end
  end

  local per_user = {}
  for _, user in ipairs(M.list_users()) do
    local user_id = user.id
    local store, storage_path = M.load_user_store(user_id)
    local config = M.get_user_config(user_id)

    local vocal_tr = M.find_track_by_guid(config.vocal_guid)
    local instrument_tr = M.find_track_by_guid(config.instrument_guid)
    local monitor_tr = M.find_track_by_guid(config.monitor_guid)

    local snapshots = {}
    for _, name in ipairs(M.list_snapshot_names(store)) do
      table.insert(snapshots, M.snapshot_summary(name, store.snapshots[name]))
    end

    per_user[user_id] = {
      storage_path = M.normalize_web_string(storage_path),
      config = {
        vocal_guid = config.vocal_guid,
        vocal_name = vocal_tr and M.normalize_web_string(M.get_track_name(vocal_tr)) or nil,
        instrument_guid = config.instrument_guid,
        instrument_name = instrument_tr and M.normalize_web_string(M.get_track_name(instrument_tr)) or nil,
        monitor_guid = config.monitor_guid,
        monitor_name = monitor_tr and M.normalize_web_string(M.get_track_name(monitor_tr)) or nil,
      },
      snapshots = snapshots,
      live_fx = {
        vocal = M.list_folder_child_tracks(vocal_tr),
        instrument = M.list_folder_child_tracks(instrument_tr),
      },
    }
  end

  return {
    updated_at = os.time(),
    project_name = M.normalize_web_string(proj_name ~= "" and proj_name or "(unsaved)"),
    active_user_id = M.get_active_user_id(),
    users = users,
    tracks = tracks,
    folder_tracks = folder_tracks,
    monitor_tracks = monitor_tracks,
    per_user = per_user,
  }
end

function M.get_bridge_generation()
  return tonumber(select(2, reaper.GetProjExtState(0, M.WEB_SECTION, "bridge_gen"))) or 0
end

function M.bump_bridge_generation()
  local gen = os.time()
  reaper.SetProjExtState(0, M.WEB_SECTION, "bridge_gen", tostring(gen))
  return gen
end

function M.prepare_web_bridge()
  M.clear_web_response()
  M.clear_web_command()
  M.write_web_state()
end

function M.stop_web_bridge()
  M.bump_bridge_generation()
  M.clear_web_response()
  M.clear_web_command()
end

function M.write_web_state()
  local json = M.get_json()
  reaper.SetProjExtState(0, M.WEB_SECTION, "state", json.encode(M.build_web_state()))
end

function M.clear_web_response()
  reaper.SetProjExtState(0, M.WEB_SECTION, "response", "")
end

function M.write_web_response(response)
  local json = M.get_json()
  local safe = {
    id = response.id,
    ok = response.ok == true,
    message = M.normalize_web_string(response.message or ""),
  }

  if response.data ~= nil then
    safe.data = response.data
  end

  reaper.SetProjExtState(0, M.WEB_SECTION, "response", json.encode(safe))
end

function M.read_web_command()
  local cmd = select(2, reaper.GetProjExtState(0, M.WEB_SECTION, "command"))
  if not cmd or cmd == "" then
    cmd = select(2, reaper.GetProjExtState(0, M.LEGACY_WEB_SECTION, "command"))
  end
  if not cmd or cmd == "" then
    return nil
  end
  local ok, decoded = pcall(function()
    return M.get_json().decode(cmd)
  end)
  if ok then
    return decoded
  end
  return nil
end

function M.clear_web_command()
  reaper.SetProjExtState(0, M.WEB_SECTION, "command", "")
end

local function web_response(cmd)
  return {
    id = cmd and cmd.id or nil,
    ok = false,
    message = "",
    errors = {},
  }
end

local function resolve_user_id(cmd)
  if cmd.user_id and cmd.user_id ~= "" then
    return cmd.user_id
  end
  return M.get_active_user_id()
end

local WEB_ACTIONS = {
  set_active_user = function(cmd, response)
    local ok, err = M.set_active_user_id(cmd.user_id)
    response.ok = ok == true
    response.message = ok and ("Switched to " .. tostring(cmd.user_id) .. ".") or tostring(err)
  end,
  create_user = function(cmd, response)
    local ok, result = M.create_user(cmd.display_name)
    response.ok = ok == true
    if ok then
      response.message = "Created musician '" .. cmd.display_name .. "'."
      response.data = { user_id = result }
    else
      response.message = tostring(result)
    end
  end,
  rename_user = function(cmd, response)
    local ok, err = M.rename_user(cmd.user_id, cmd.display_name)
    response.ok = ok == true
    response.message = ok and "Musician renamed." or tostring(err)
  end,
  delete_user = function(cmd, response)
    local ok, err = M.delete_user(cmd.user_id)
    response.ok = ok == true
    response.message = ok and "Musician deleted." or tostring(err)
  end,
  set_config = function(cmd, response)
    M.set_user_config(resolve_user_id(cmd), cmd.vocal_guid, cmd.instrument_guid, cmd.monitor_guid)
    response.ok = true
    response.message = "Track configuration saved."
  end,
  capture = function(cmd, response)
    local ok, err = M.capture_and_save(cmd.name, resolve_user_id(cmd))
    response.ok = ok == true
    response.message = ok and ("Captured '" .. cmd.name .. "'.") or tostring(err)
  end,
  update = function(cmd, response)
    local user_id = resolve_user_id(cmd)
    local tracks = M.get_config_tracks(user_id)
    local snapshot, err = M.capture_snapshot(tracks.vocal_tr, tracks.instrument_tr, tracks.monitor_tr)
    if not snapshot then
      response.message = tostring(err)
      return
    end
    local ok, save_err = M.save_named_snapshot(cmd.name, snapshot, user_id)
    response.ok = ok == true
    response.message = ok and ("Updated '" .. cmd.name .. "'.") or tostring(save_err)
  end,
  load = function(cmd, response)
    local ok, errors = M.load_and_apply(cmd.name, resolve_user_id(cmd))
    response.ok = ok == true
    response.errors = errors or {}
    response.message = ok and ("Loaded '" .. cmd.name .. "'.") or table.concat(response.errors, "\n")
  end,
  delete = function(cmd, response)
    local ok, err = M.delete_named_snapshot(cmd.name, resolve_user_id(cmd))
    response.ok = ok == true
    response.message = ok and "Snapshot deleted." or tostring(err)
  end,
  rename = function(cmd, response)
    local ok, err = M.rename_snapshot(cmd.name, cmd.new_name, resolve_user_id(cmd))
    response.ok = ok == true
    response.message = ok and "Snapshot renamed." or tostring(err)
  end,
  get_snapshot = function(cmd, response)
    local user_id = resolve_user_id(cmd)
    local snapshot, err = M.get_named_snapshot(cmd.name, user_id)
    if not snapshot then
      response.message = tostring(err)
      return
    end

    local max_fx_chars = cmd.full_fx and 8000 or 1500
    local debug_data = {
      name = cmd.name,
      user_id = user_id,
      storage_path = M.normalize_web_string(M.get_storage_path(user_id)),
      snapshot = M.snapshot_for_debug(snapshot, { max_fx_chars = max_fx_chars }),
    }

    local encoded = M.get_json().encode({ data = debug_data })
    if #encoded > 14000 then
      max_fx_chars = cmd.full_fx and 2000 or 500
      debug_data.snapshot = M.snapshot_for_debug(snapshot, { max_fx_chars = max_fx_chars })
      encoded = M.get_json().encode({ data = debug_data })
    end
    if #encoded > 14000 then
      debug_data.snapshot = M.snapshot_for_debug(snapshot, { max_fx_chars = 0 })
      debug_data.fx_chains_omitted = true
      encoded = M.get_json().encode({ data = debug_data })
    end

    response.ok = true
    response.message = "Snapshot debug data ready."
    response.data = debug_data
  end,
}

function M.handle_web_command(cmd)
  local response = web_response(cmd)
  if not cmd or not cmd.action then
    response.message = "Missing action."
    return response
  end

  local handler = WEB_ACTIONS[cmd.action]
  if not handler then
    response.message = "Unknown action: " .. tostring(cmd.action)
    return response
  end

  handler(cmd, response)
  return response
end

return M

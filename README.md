# Preset Tenderizer

**Preset Tenderizer** saves and restores complete monitoring setups for live performance in REAPER. A snapshot captures:

- **FX chains** on tracks inside the vocal and instrument folder tracks (not on the folders themselves)
- **Monitor receives** from those folder tracks to the monitoring track: levels, pan, mute, phase, mono, send mode, and channel mappings
- **Track names** on child FX tracks, set to the **primary plugin preset name** (skips FX containers) on capture and load

## Musicians

Each **musician** has their own:

- Snapshot collection (same snapshot names can exist per musician without clashing)
- Vocal folder, instrument folder, and monitor track mapping

Use the **Musician** dropdown and **Manage** in the web UI to add, rename, delete, and switch musicians. Each browser tab remembers its own selected musician via `sessionStorage`, so you can open multiple tabs for different band members without them fighting over the dropdown. Capture, load, and track mapping in the web UI always target the musician selected in that tab.

The project still stores a default **active musician** (`active_user_id` in ProjExtState). OSC/MIDI actions use that default unless overridden with `MUSICIAN_ID` in `PresetTenderizer_LoadByName.lua`. Loading or capturing from the web UI still affects the shared REAPER project session.

## Web UI setup

Uses REAPER's built-in web server (`reaper_www_root` + `main.js`). No Node or npm.

1. Install the [`PresetTenderizer/`](PresetTenderizer/) folder in your REAPER Scripts directory (all `PresetTenderizer*.lua` files and `www_root/` together).
2. Run **PresetTenderizer_StartWebUI** (installs web files + starts the bridge). Use **PresetTenderizer_RestartWebUI** after code updates or if the page shows a stale connection. Run **PresetTenderizer_StopWebUI** to stop the bridge.
3. In REAPER: **Preferences → Control/OSC/Web → Add → Web browser interface**.
4. Select **PresetTenderizer.html** and open the **Access URL** (e.g. `http://127.0.0.1:8080/PresetTenderizer.html`).
5. Keep the web bridge running while using the page (StartWebUI starts it; re-run if needed).

After code updates, run **PresetTenderizer_InstallWebUI** or **PresetTenderizer_RestartWebUI** and hard-refresh the browser.

## Performance actions (OSC / MIDI / Stream Deck)

| Script | Use |
|--------|-----|
| `PresetTenderizer/PresetTenderizer_LoadByName.lua` | Edit `SNAPSHOT_NAME`; optional `MUSICIAN_ID` at top of file |
| `PresetTenderizer/PresetTenderizer_SaveCurrent.lua` | Prompt and save current state (active musician) |

## Files

All scripts and web assets live under [`PresetTenderizer/`](PresetTenderizer/):

| File | Purpose |
|------|---------|
| `PresetTenderizer/PresetTenderizer_lib.lua` | Capture, restore, storage, musicians, web command handling |
| `PresetTenderizer/PresetTenderizer_json.lua` | JSON encode/decode |
| `PresetTenderizer/PresetTenderizer_action.lua` | Shared logic for action scripts |
| `PresetTenderizer/PresetTenderizer_WebBridge.lua` | Web UI bridge (ProjExtState) |
| `PresetTenderizer/PresetTenderizer_InstallWebUI.lua` | Copy `www_root/` into `reaper_www_root` |
| `PresetTenderizer/PresetTenderizer_StartWebUI.lua` | Install + start bridge |
| `PresetTenderizer/PresetTenderizer_RestartWebUI.lua` | Reinstall web files + restart bridge |
| `PresetTenderizer/PresetTenderizer_StopWebUI.lua` | Stop the web bridge |
| `PresetTenderizer/www_root/PresetTenderizer.html` | Web page |
| `PresetTenderizer/www_root/PresetTenderizer.css` | Styles |
| `PresetTenderizer/www_root/PresetTenderizer.js` | Web logic (`wwr_req`) |

## Storage

```
<project>/PresetTenderizer/
  users.json
  users/<musician_id>/snapshots.json
```

Legacy `MonitoringSnapshots/snapshots.json` and flat ProjExtState config are migrated into the `default` musician on first load.

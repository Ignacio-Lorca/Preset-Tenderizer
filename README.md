# Preset Tenderizer

**Preset Tenderizer** is a lightweight Lua script generator for REAPER that helps you manage and switch guitar track FX presets on a per-song basis. Inspired by the smooth blending of flavors in a meat marinade, this tool "tenderizes" your workflow by automating preset changes with dedicated scripts.

---

## Features

- Define presets per track and FX plugin easily.
- Generate one standalone REAPER Lua script per song.
- Each generated script applies the configured presets and renames tracks accordingly.
- Simplifies preset management without needing complex GUI interactions.
- Designed for guitar FX chains but adaptable to other instruments.

---

## Preset Tenderizer
Preset Tenderizer is a streamlined REAPER Lua scripting tool designed to make switching guitar FX presets per song easy and fast. Instead of complex GUIs, it uses two simple script types:

Reader script: Runs in REAPER to read the current preset combinations on your tracks and generates a formatted preset list you can copy.

Changer scripts: You paste the copied preset list into a standalone script that includes a core “preset apply” module. Each changer script applies the presets for a specific song.

## How It Works
Run the reader script in REAPER. It scans your tracks and effects, then outputs a formatted preset list.

Copy the preset list from the REAPER console.

Create a new changer script file and paste the copied list into it.

The changer script includes a shared preset-application module that handles the actual setting of presets and renaming tracks.

Trigger the changer script via toolbar button or OSC to switch to that song’s presets instantly.

## Dependencies

REAPER with Lua scripting enabled.

Place all scripts in your REAPER scripts folder (e.g., C:\Users\<user>\AppData\Roaming\REAPER\Scripts).

The changer scripts include a shared Lua file (preset_changer_core.lua) which handles applying presets and track renaming.

## Benefits

No manual editing of Lua tables — just copy and paste output from the reader.

Keeps preset application logic in one reusable module.

Easy to create a new song preset script in seconds.

Lightweight and requires no external UI libraries or dependencies.


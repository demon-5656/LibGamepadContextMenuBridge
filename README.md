# LibGamepadContextMenuBridge

Standalone ESO library addon repository.

This library mirrors inventory actions registered via `LibCustomMenu:RegisterContextMenu(...)` into gamepad action lists.
It also supports gamepad submenu dialogs for `AddCustomSubMenuItem(...)` entries.

## Repository Layout
- `LibGamepadContextMenuBridge/` - addon files for `Documents/Elder Scrolls Online/live/AddOns/`
- `scripts/build_release.sh` - builds `.zip` (or `.tar.gz` fallback) release archive

## Dependencies
- Required: `LibCustomMenu`

## Install (manual)
Copy the folder below into your ESO AddOns directory:
- `LibGamepadContextMenuBridge/`

Target path:
`~/Documents/Elder Scrolls Online/live/AddOns/LibGamepadContextMenuBridge/`

## Build Release Archive
```bash
bash scripts/build_release.sh
```

Output files are written to `dist/`.

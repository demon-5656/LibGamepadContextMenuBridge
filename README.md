# LibGamepadContextMenuBridge

Standalone ESO library addon repository.

This library mirrors inventory actions registered via `LibCustomMenu:RegisterContextMenu(...)` into gamepad action lists.
It allows keyboard/mouse context actions from compatible addons to be used in gamepad mode.

## How the bridge behaves
1. Hooks `LibCustomMenu:RegisterContextMenu(...)` and stores context callbacks.
2. On gamepad item-action refresh, rebuilds custom context entries for the current slot.
3. Converts supported entries to gamepad `slotActions`.
4. Executes the original callback when a mirrored action is selected.

## Which entries are mirrored
- `AddCustomMenuItem(...)` actionable rows.
- `AddCustomSubMenuItem(...)` parent rows.
- Submenu children in a dedicated gamepad submenu dialog.
- Entries in `LibCustomMenu` category order (`EARLY` to `LATE`).

## Which entries are skipped
- Dividers, headers, and non-action rows.
- Disabled entries without executable callbacks.
- Entries not generated for the current slot.
- Duplicate actions already present in the gamepad list.

## Repository Layout
- `LibGamepadContextMenuBridge/` - addon files for `Documents/Elder Scrolls Online/live/AddOns/`
- `scripts/build_release.sh` - builds `.zip` (or `.tar.gz` fallback) release archive

## Dependencies
- Required: `LibCustomMenu>=730`
- Optional: `LibAddonMenu-2.0` (settings panel)

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

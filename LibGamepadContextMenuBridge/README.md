# LibGamepadContextMenuBridge

ESO library addon that mirrors inventory entries created via `LibCustomMenu:RegisterContextMenu(...)` into gamepad inventory action lists.

## What it does
- Captures context menu entries added through `AddCustomMenuItem` and `AddCustomSubMenuItem`.
- Injects them into gamepad `slotActions` as secondary actions.
- Keeps category order (`EARLY` to `LATE`).
- Skips non-action entries (headers/dividers/disabled entries).
- Opens real submenus in a gamepad selection dialog (instead of flattening all submenu items into one list).

## Usage
1. Install folder `LibGamepadContextMenuBridge` into `AddOns`.
2. Enable it in the addon list.
3. No code changes required for addons already using `LibCustomMenu:RegisterContextMenu`.

## Optional API
```lua
LibGamepadContextMenuBridge:SetEnabled(true)
LibGamepadContextMenuBridge:RegisterContextMenu(function(inventorySlot, slotActions)
    -- optional manual callback registration
end, LibCustomMenu.CATEGORY_LATE)
```

## Notes
- Submenu entries open a dedicated gamepad submenu dialog.
- Callbacks that rely on mouse-only UI controls may need per-addon adjustments.

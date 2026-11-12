# LibGamepadContextMenuBridge

**AI disclosure:** AI was used for code generation, refactoring and documentation. Author: **Azmail**. See [credits](CREDITS.md).

ESO library addon that mirrors inventory entries created via `LibCustomMenu:RegisterContextMenu(...)` into gamepad inventory action lists.

## Purpose
This library makes keyboard/mouse context actions available when playing in gamepad mode.
It is designed for addons that already register inventory context actions through `LibCustomMenu`.

## How it works
1. Uses `LibCustomMenu`'s own context registry without wrapping registration or keeping a duplicate callback cache.
2. When a gamepad item action list is refreshed, it asks the `LibCustomMenu` registries to build context entries for the current slot.
3. It converts supported context entries into gamepad `slotActions` entries.
4. Pressing an injected action runs the original callback from the context menu entry.

## What will be shown in gamepad actions
- Regular custom actions added with `AddCustomMenuItem(...)` that are actionable.
- Submenu parents with their own click callback, as independent actions.
- Submenu children flattened into `Parent: Child` actions.
- Entries in the same category execution order as `LibCustomMenu` (`EARLY` -> `NORMAL` -> `LATE`).

## What will NOT be shown
- Divider/header/non-action rows.
- Disabled entries (entries without an executable callback).
- Entries that are not produced for the current inventory slot by the originating addon callback.
- Duplicate entries already present in the current gamepad action list.

## Submenu behavior
- A parent's click callback is injected as a separate action, including for an empty submenu.
- Children appear directly in the gamepad action list as `Parent: Child`.
- Selecting a child runs only its callback, not the parent's callback.
- Checkbox children receive their new boolean state, while ordinary actions receive no arguments.
- An action that throws propagates its error and is not automatically repeated. Menu-building failures restore temporary capture state before propagating the original traceback.

## Usage
1. Install folder `LibGamepadContextMenuBridge` into `AddOns`.
2. Enable it in the addon list.
3. No code changes are required for addons that already use `LibCustomMenu:RegisterContextMenu`.

## Optional API
```lua
LibGamepadContextMenuBridge:SetEnabled(true)
LibGamepadContextMenuBridge:RegisterContextMenu(function(inventorySlot, slotActions)
    -- optional manual callback registration
end, LibCustomMenu.CATEGORY_LATE)
```

## Dependency requirements
- `LibCustomMenu>=730`
- Optional: `LibAddonMenu-2.0` (for settings panel; integration checked against r43)
- Optional: `TamrielTradeCentre` and its price data (for market prices).

## Compatibility
The manifest targets ESO Live API **101051**, not PTS API 101052. The addon remains beta and targets the desktop client; console support is not claimed. The native-tooltip userdata fix from 1.5.4 is retained.

Required dependency minimums use the library's integer `AddOnVersion`. Optional dependencies only arrange load order and have no `>=` requirement. `PCDependsOn` / `ConsoleDependsOn` specify platform-specific required dependencies, not optional ones.

## Server settings and deferred hooks
- Settings are account-wide per server. EU and NA settings can differ.
- Each server's first load inherits the old shared settings without deleting them; existing server settings are not overwritten.
- Hooks are installed on first gamepad activation, not directly at addon load. Disabled/keyboard mode skips overlay work, unregisters overlay events and cancels pending hook retries.
- Closing a Trading House or crafting interaction unregisters its close listener. Enabling the bridge during an already-open interaction also restores the matching close listener.

## Settings and Debug
- Addon panel: `Settings -> Addon Settings -> LibGamepadContextMenuBridge` (requires `LibAddonMenu-2.0`).
- Available toggles: enable bridge, debug mode, verbose debug.
- Slash command: `/lgcmb`
  - `/lgcmb status`
  - `/lgcmb on` or `/lgcmb off`
  - `/lgcmb debug on` or `/lgcmb debug off`
  - `/lgcmb verbose on` or `/lgcmb verbose off`
  - `/lgcmb log 60`
  - `/lgcmb clearlog`

# LibGamepadContextMenuBridge Review Notes

## Task

Address review feedback for `LibGamepadContextMenuBridge` so the library follows safer ESO addon initialization rules and avoids unnecessary category fallbacks when `LibCustomMenu` is guaranteed by `## DependsOn: LibCustomMenu>=730`.

Primary changes requested:

1. Remove `or 1` / `or 6` style fallbacks around `lcm.CATEGORY_EARLY` and `lcm.CATEGORY_LATE` where `LibCustomMenu` is already expected to exist.
2. Do not register runtime events like `EVENT_PLAYER_ACTIVATED` directly at file scope.
3. Keep registrations that may depend on `SavedVariables` behind `EVENT_ADD_ON_LOADED`, including the general rule for slash commands and other event-based initialization.

## What We Found

### Addon metadata

File: `LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.txt`

- The addon already declares `## DependsOn: LibCustomMenu>=730`.
- Because of that dependency, `LibCustomMenu` should be available before this addon initializes.

### Category fallback usage

File: `LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua`

We found category fallback patterns in these places:

- `ResolveCategory(lcm, category)`
  - currently uses `lcm and lcm.CATEGORY_EARLY or 1`
  - currently uses `lcm and lcm.CATEGORY_LATE or 6`
- `bridge:_summarizeContextRegistry()`
  - currently uses `(LibCustomMenu and LibCustomMenu.CATEGORY_EARLY) or 1`
  - currently uses `(LibCustomMenu and LibCustomMenu.CATEGORY_LATE) or 6`
- `bridge:_invokeRawRegistryHandlers(lcm, inventorySlot, slotActions)`
  - currently uses `lcm.CATEGORY_EARLY or 1`
  - currently uses `lcm.CATEGORY_LATE or 6`
- `bridge:_runContextCallbacks(lcm, inventorySlot, slotActions)`
  - currently uses `lcm.CATEGORY_EARLY or 1`
  - currently uses `lcm.CATEGORY_LATE or 6`

Review feedback says these `or` fallbacks are unnecessary if dependency handling is correct. If a local fallback is still desired for defensive code paths, it should be expressed explicitly with local constants instead of `lcmValue or literal`.

### Event registration at file scope

File: `LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua`

At the bottom of the file we found:

- `EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED, OnAddonLoaded)`
- `EVENT_MANAGER:RegisterForEvent(PLAYER_ACTIVATED_EVENT_NAMESPACE, EVENT_PLAYER_ACTIVATED, function() ... end)`

The review concern is valid for `EVENT_PLAYER_ACTIVATED`: it is currently registered immediately when the Lua file is loaded, before `OnAddonLoaded` has run.

Risk described by the reviewer:

- a runtime event may fire before `EVENT_ADD_ON_LOADED` finishes
- if any handler uses `SavedVariables` before `_initializeSavedVars()`, it can fail
- the same rule should be applied to slash commands and any similar initialization

### SavedVariables initialization path

File: `LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua`

Current flow:

- `OnAddonLoaded()` calls `bridge:Initialize()`
- `bridge:Initialize()` calls:
  - `self:_initializeSavedVars()`
  - `self:_initializeSlashCommands()`
  - `self:_initializeSettingsPanel()`

This means:

- slash commands are already initialized only after `EVENT_ADD_ON_LOADED`
- settings panel setup is already initialized only after `EVENT_ADD_ON_LOADED`
- `SavedVariables` are loaded before slash commands are registered

So the slash-command part of the review is already satisfied by the current implementation.

### What still needs changing in code

Based on the review and the current implementation, the remaining code changes are:

1. Move `EVENT_PLAYER_ACTIVATED` registration out of file scope and into the initialization path that runs after `EVENT_ADD_ON_LOADED`.
2. Replace the `CATEGORY_EARLY` / `CATEGORY_LATE` `or` fallbacks with either:
   - direct use of `LibCustomMenu` values where the dependency guarantees availability, or
   - explicit local constants used through normal conditional logic.

## Recommended implementation direction

- Keep `EVENT_ADD_ON_LOADED` registration at file scope.
- Inside `bridge:Initialize()` or inside `OnAddonLoaded()` after `SavedVariables` initialization, register `EVENT_PLAYER_ACTIVATED`.
- Leave slash commands where they are now, because they are already initialized after `SavedVariables`.
- Replace the category fallback expressions consistently in all four locations listed above.

## Relevant file

- `LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua`

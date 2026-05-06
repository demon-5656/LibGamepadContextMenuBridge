# Changelog

## 1.4.5
- Fixed crafting-station tooltip info (TTC price, bound status) never appearing in gamepad mode.
  `_hookCraftingTooltips()` was defined but never called from `Initialize()` — now it is.
- Added `ZO_GamepadSmithingCreation.SetupResultTooltip` hook for gamepad smithing / clothier /
  woodworking stations.  The gamepad class overrides this method and uses its own `resultTooltip.tip`
  floating control instead of the shared `GAMEPAD_TOOLTIPS` pool, so a dedicated hook is required.
- Added `_hookTradingHouseTooltip()`: post-hooks `GAMEPAD_TOOLTIPS:LayoutGuildStoreSearchResult`
  so that TTC price / vendor / bound info is appended to the right-panel tooltip whenever an item
  is selected in the gamepad Trading House browse results.
- Both new hooks are also retried on `EVENT_PLAYER_ACTIVATED` in case globals are not yet
  available during the initial `EVENT_ADD_ON_LOADED` pass.

## 1.4.4
- Fixed tooltip info (TTC price, bound status) not appearing during crafting in gamepad mode.
  Crafting station tooltips use `LayoutItemLink` instead of `LayoutBagItem`; the bridge now hooks both.
  Added `_appendGamepadTooltipInfoByLink` helper for item-link–based tooltip augmentation.

## 1.4.3
- Optimized the gamepad tooltip hot path by caching TTC tooltip lines and preformatted colored text.
- Reduced repeated string work and removed unnecessary verbose processing from the frequent tooltip render path.
- Preserved the 1.4.2 visual polish while preparing the remaining action-menu path for follow-up performance tuning.

## 1.4.2
- Refined the gamepad tooltip price block layout for cleaner spacing and more readable hierarchy.
- Reduced the visual size of the custom tooltip block and shortened TTC detail values with compact `k` / `kk` formatting.
- Kept tooltip integration compatible with existing gamepad inventory flows while preparing for follow-up performance work.

## 1.4.0
- Added native gamepad `Mark as Junk` / `Unmark as Junk` fallback action for inventory items, so the missing junk toggle can be restored without relying on a third-party gamepad inventory UI.
- Added an optional gamepad tooltip info block with TTC pricing, optional min/avg/max listing details, junk status, bound status, and vendor value.
- Added LibAddonMenu toggles for the new tooltip info block features.
- Improved hook safety by preferring `SecurePostHook` for inventory action integration and by retrying tooltip hook registration after player activation.

## 1.4.1
- Fixed TTC tooltip prices not appearing in gamepad tooltips by appending bridge lines after the base tooltip layout.
- Expanded TTC detail output to include listing counts, sale averages, sale counts, and TTC price-table update text when available.
- Moved `EVENT_PLAYER_ACTIVATED` registration into addon initialization to avoid unsafe event timing before `EVENT_ADD_ON_LOADED`.
- Removed hardcoded `LibCustomMenu` category fallback values and now rely on the dependency-provided constants directly.
- Fixed release packaging so rebuilt zip archives do not accumulate stale entries from previous builds.

## 1.3.3
- Simplified addon initialization to a single `EVENT_ADD_ON_LOADED` path for this library only.
- Added strict dependency requirement `LibCustomMenu>=730`.
- Clarified behavior documentation: which context entries are mirrored, how submenus are shown, and which entries are intentionally skipped.

## 1.3.0
- Fixed gamepad capture for `LibCustomMenu` callbacks by invoking `contextMenuRegistry:FireCallbacks` and adding fallback handler invocation.
- Added slot-type normalization for gamepad inventory context (`SLOT_TYPE_ITEM`/bank variants), improving compatibility with mods that gate by slot type.
- Added `LibAddonMenu-2.0` settings panel and debug tooling (`/lgcmb`, verbose traces, in-memory debug log).
- Improved initialization timing/hook resilience for late-loaded UI components.
- Added compatibility with custom gamepad action dialogs by stamping custom action labels and string ids.
- Switched submenu behavior to flattened gamepad actions for reliable execution across UI variants.

## 1.1.0
- Added real gamepad submenu dialog support for `AddCustomSubMenuItem`.
- Improved capture safety and callback isolation.
- Added compatibility guard to avoid duplicate actions with PersonalAssistant custom gamepad hooks.

## 1.0.0
- Initial release.
- Mirrored `LibCustomMenu` inventory context actions into gamepad actions.

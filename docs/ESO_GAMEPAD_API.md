# ESO gamepad API: current reference

This replaces the old implementation notes. For verified source contracts and acceptance boundaries, use [API_CONTRACTS_101051.md](API_CONTRACTS_101051.md). The [platform specification](PLATFORM_SPEC.md) is a proposal, not an available provider API.

The reviewed native snapshot is ESO UI Live API **101051**, commit `f819c808d57e237707c76e7b52518e2589c9e191` (checked 12 November 2026). This is source evidence, not an in-game pass for bridge 1.5.5.

- Inventory information uses `LayoutBagItem`; Trading House information uses `LayoutGuildStoreSearchResult`.
- Trading House browse results expose `GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS:GetSelectedData()`. The BrowseResults class is local. Do not use an assumed `itemList:GetTargetData()` path or scan for a similar item.
- Crafting result information comes from `ZO_GamepadSmithingCreation:SetupResultTooltip`, `ZO_GamepadProvisioner:RefreshRecipeDetails`, `ZO_GamepadAlchemy:UpdateTooltip` and `ZO_GamepadEnchanting:UpdateTooltip`.
- `LayoutFurnishingCraftingResult` is not a verified API and must not be used. Earlier pending-info/prehook instructions and claims of dynamically installed methods are withdrawn.
- Tooltip content and its owner/container are different objects. A mixed-in tooltip's `GetParent()` is a styled-object parent, not native ancestry. Use the manager's `GetTooltipContainer(type)` or the actual crafting result panel explicitly.
- Ordinary supported menu actions take no arguments; supported submenu checkbox children take a boolean. Mouse parent and top-level checkbox callbacks need real controls and are not emulated.

Geometry, scrolling, secure behavior and current addon compatibility still require [game acceptance](ACCEPTANCE_AND_RELEASE.md).

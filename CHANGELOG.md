# Changelog

## 1.5.5 — beta

- Restores missing TTC prices and refreshes displayed prices when data changes.
- Prevents repeated menu building and cancels actions if the selected item has changed.
- Preserves compatible addons' keybinds and removes menu entries when their addon clears them.
- Removes old prices when a tooltip changes to another type of item.
- Corrects crafting comparisons for recipes that produce multiple items.
- Keeps EU and NA settings separate while preserving existing preferences.
- Supports flat submenu entries and checkbox toggles; some mouse-only actions are omitted.

## Earlier versions

### 1.5.4
- Corrected the startup error affecting native inventory and Trading House tooltips in 1.5.3.

### 1.5.3
- Updated the ESO compatibility target and dependency declarations.
- Revised inventory actions, crafting quantities and selected Trading House lot handling.
- Added AI disclosure and credits.

### 1.5.2
- Stopped retrying failed actions and replaying empty menus.
- Cancelled delayed information updates after selection changes or closing the overlay.
- Revised flat submenu actions and checkbox children.
- Included all known ingredients in material totals and marked incomplete estimates.

### 1.5.1
- Moved item information into a separate panel and revised its placement.
- Expanded crafting material estimates and improved their presentation.

### 1.4.6
- Reduced repeated work while updating Trading House item information.

### 1.4.5
- Corrected missing item information at crafting stations and in Trading House results.

### 1.4.4
- Corrected missing information in crafting tooltips.

### 1.4.3
- Reduced repeated work when displaying price information.

### 1.4.2
- Refined the price panel's spacing, size and compact number formatting.

### 1.4.1
- Corrected missing TTC tooltip prices and added more available price details.
- Corrected release archive rebuilding so old entries did not accumulate.

### 1.4.0
- Added mark/unmark as junk, optional item information and settings for it.

### 1.3.3
- Required LibCustomMenu 7.3.0 or newer and clarified supported menu entries.

### 1.3.0
- Revised inventory menu integration, added settings and switched to flat submenu actions.

### 1.1.0
- Added submenu support and reduced duplicate actions with some gamepad interfaces.

### 1.0.0
- Initial inventory-action bridge for LibCustomMenu.

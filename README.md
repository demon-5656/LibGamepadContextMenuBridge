# LibGamepadContextMenuBridge

Use inventory actions from compatible keyboard/mouse addons while playing ESO with a gamepad.

The bridge brings actions registered through **LibCustomMenu** into the gamepad item-action menu. Existing compatible addons do not need to be modified.

## Features

- Custom inventory actions in the gamepad menu.
- Submenu actions displayed as `Parent: Child`, including checkbox actions.
- Mark/unmark items as junk.
- Optional TTC prices, vendor value and item-status information.
- Crafting material cost estimates, with incomplete prices marked accordingly.
- Separate account-wide settings for EU and NA.

## Requirements

- **LibCustomMenu 7.3.0 or newer** (`AddOnVersion >= 730`).
- Optional: **LibAddonMenu-2.0** for the settings panel.
- Optional: **Tamriel Trade Centre** and its price data for market prices.

Targets the desktop client, ESO API **101051**. Version **1.5.5** is in development.

## Installation

Place the `LibGamepadContextMenuBridge` folder in your ESO `live/AddOns` directory and enable it alongside LibCustomMenu.

Settings: **Settings → Addon Settings → LibGamepadContextMenuBridge**.
Without LibAddonMenu, use `/lgcmb` for commands or `/lgcmb on` and `/lgcmb off` to toggle the bridge.

## Compatibility

Supports inventory actions registered through `LibCustomMenu:RegisterContextMenu`. It does not convert arbitrary keyboard-only interfaces. Headers, dividers and disabled actions are not shown; submenu children appear directly in the gamepad action list.

## Documentation

- [Changelog](CHANGELOG.md)
- [Addon API and commands](LibGamepadContextMenuBridge/README.md)
- [Developer API notes](docs/API_CONTRACTS_101051.md)
- [Roadmap](docs/PRODUCT_STRATEGY.md) · [Proposed platform API](docs/PLATFORM_SPEC.md) · [Acceptance and release](docs/ACCEPTANCE_AND_RELEASE.md)

## Author and credits

**Azmail**. AI was used for code generation, refactoring and documentation. See [credits](LibGamepadContextMenuBridge/CREDITS.md).

This add-on is not created by, affiliated with, or sponsored by ZeniMax Media Inc. or its affiliates.

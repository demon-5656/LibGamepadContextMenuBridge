# LibGamepadContextMenuBridge

**AI disclosure:** AI was used for code generation, refactoring and documentation. Author: **Azmail**. See [credits](LibGamepadContextMenuBridge/CREDITS.md).

Standalone ESO library addon repository.

This library mirrors inventory actions registered via `LibCustomMenu:RegisterContextMenu(...)` into gamepad action lists.
It allows keyboard/mouse context actions from compatible addons to be used in gamepad mode.

It also includes optional quality-of-life additions for gamepad inventory users:
- native `Mark as Junk` / `Unmark as Junk` fallback when the base gamepad menu does not expose the junk action
- optional tooltip info block for TTC price, TTC detail summary, junk status, bound status, and vendor value

## How the bridge behaves
1. Uses the context registry provided by the required `LibCustomMenu>=730`; it does not maintain a second callback cache.
2. On gamepad item-action refresh, rebuilds custom context entries for the current slot.
3. Converts supported entries to gamepad `slotActions`.
4. Executes the original callback when a mirrored action is selected.

## Which entries are mirrored
- `AddCustomMenuItem(...)` actionable rows.
- `AddCustomSubMenuItem(...)` parents with their own click callback, as independent actions.
- Submenu children flattened into `Parent: Child` actions; selecting a child does not run the parent callback.
- Entries in `LibCustomMenu` category order (`EARLY` to `LATE`).

## Which entries are skipped
- Dividers, headers, and non-action rows.
- Disabled entries without executable callbacks.
- Entries not generated for the current slot.
- Duplicate actions already present in the gamepad list.

## Repository Layout
- `LibGamepadContextMenuBridge/` - addon files for `Documents/Elder Scrolls Online/live/AddOns/`
- `scripts/build_release.sh` - builds `.zip` (or `.tar.gz` fallback) release archive
- `scripts/tests/regression.lua` - deterministic callback, overlay, dispatch, submenu, and material-estimate checks

## Development Roadmap

Документация перехода от полезного моста к востребованному инструменту для игроков и платформе для авторов:

- [От «просто мод» к «мне это точно нужно»](docs/PRODUCT_STRATEGY.md) — ценность для игрока, приоритеты, этапы и первый backlog.
- [Проект платформы и API](docs/PLATFORM_SPEC.md) — границы core, provider/context/action contracts и миграция без поломки legacy.
- [Приёмка, пилот и выпуск](docs/ACCEPTANCE_AND_RELEASE.md) — игровые сценарии, критерии готовности, демонстрация пользы и публикация.

Это планы и требования, а не список уже реализованных возможностей. Предлагаемый provider API пока отсутствует в 1.5.2; текущий способ подключения описан в [addon README](LibGamepadContextMenuBridge/README.md).

## Local Regression Checks
From the repository root, run `lua scripts/tests/regression.lua`.
These tests use explicit ESO/TTC stubs; they do not replace an in-game check.
Crafting material totals include ingredients beyond the eight displayed detail rows.
Missing prices produce a partial/incomplete estimate without a crafted-value comparison.

## Dependencies
- Required: `LibCustomMenu>=730`
- Optional: `LibAddonMenu-2.0>=43` (settings panel)
- Optional for price display: `TamrielTradeCentre`

The manifest targets **API 101051**. Contracts are checked against the pinned ESO UI sources; see [API verification](docs/API_CONTRACTS_101051.md).

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

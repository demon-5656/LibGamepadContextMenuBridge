# Publication drafts: 1.5.5

Owner review only. Nothing is published. Use `ESOUI_DESCRIPTION.bbcode` for the English-only page description. Keep AI disclosure at the beginning of the public description.

## Short update note (English)

**1.5.5 — beta**

- Restores missing TTC prices and refreshes displayed prices when data changes.
- Prevents repeated menu building and cancels actions if the selected item has changed.
- Preserves compatible addons' keybinds and clears removed menu entries correctly.
- Removes old prices when the tooltip changes to another type of item.
- Corrects crafting comparisons for recipes that produce multiple items.
- Keeps EU and NA settings separate while preserving existing preferences.
- Supports flat submenu entries and checkbox toggles; some mouse-only actions are omitted.

Implemented and tested locally; testing in ESO is still required.

## Before publishing

Compare this text with the final implementation and completed acceptance record. Do not add claims about review fixes until they are implemented and checked. Retain test status unless game acceptance actually changes it. Do not reuse the historical `forum_post_v1.4.1.txt` as the current description.

Confirm the existing ESOUI page/channel, author credits, required LibCustomMenu>=730, optional LAM/TTC with data, and final package license/content. Python 3 is needed only for the maintainer's packaging tools, not for players. Building a real ZIP and publishing require a separate owner decision; neither is authorized by these drafts.

# Publication notes: 1.5.5

Published on GitHub as prerelease `v1.5.5`, built from commit `dcd82cf8bb7f9f96b3db01d5eb5557d911ffe3be`. Submitted to the existing ESOUI addon page `4432`; moderator approval is pending as of November 12, 2026. Submission is not confirmation of public download availability.

The GitHub asset was downloaded and compared byte-for-byte with the local ZIP. SHA-256: `91ce56d956a12fc71501bedee06427e94098ca237bebd4bc19d2197b39c897db`.

ESOUI's saved version, archive name, English description and changelog were read back after submission. AI disclosure is at the beginning; dependencies, credits and beta limitations are included. Existing compatibility selections and screenshots were preserved, and the previous archive was retained. The public ESOUI ZIP still needs verification after moderator approval.

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

Confirm the existing ESOUI page/channel, author credits, required LibCustomMenu>=730, optional LAM/TTC with data, and final package license/content. Python 3 is needed only for the maintainer's packaging tools, not for players. Building a real ZIP and publishing require an explicit owner decision.

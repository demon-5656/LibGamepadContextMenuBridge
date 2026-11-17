# Maintenance conventions

## Lua methods, receivers and callbacks

Based on Baertram's explanation in the ESOUI discussion supplied by Azmail. This is a readability and maintenance recommendation, not an ESO restriction or a requirement to rewrite working code.

### Plain tables support methods

A metatable is not required for colon syntax. Defining `function bridge:Method(arg)` is shorthand for `function bridge.Method(self, arg)`. Calling `bridge:Method(arg)` passes `bridge` as the first argument, equivalent to `bridge.Method(bridge, arg)` for this simple receiver expression.

`self` is an ordinary parameter. It is not automatically bound to the table when the function is retrieved, and it does not automatically refer to a caller's surrounding scope. A function defined with colon syntax can be called through a function reference, provided the correct receiver is supplied explicitly.

### Project conventions

- Keep colon methods for operations that read or modify bridge state. A singleton table is a valid receiver; having only one instance does not make colon syntax incorrect.
- Prefer local functions for stateless implementation helpers. Pass only the data they need; do not add an unused `self` parameter merely to group functions under a table.
- Where an existing public stateless function is exposed through a table, preserve its documented dot-call signature rather than changing callers implicitly.
- Preserve existing public API signatures. Do not mechanically replace every `self` reference with `bridge`, or convert methods between dot and colon syntax solely for style.

### Callback boundaries

Passing `bridge.Method` does not bind `bridge`. The event manager, timer, hook or other callback dispatcher determines the actual arguments. If a method is passed without binding, its `self` parameter receives the dispatcher's first argument, or nil when no argument is supplied. Other parameters can consequently shift as well.

- Check each dispatcher's actual callback contract, including argument order and any explicit receiver support.
- For a stateful method, use a wrapper that passes the intended receiver and the expected callback arguments, unless the API explicitly supports binding that receiver itself.
- Stateless callbacks need no artificial receiver.
- Do not mix up an inventory control, slot-actions object, event code or another callback argument with the bridge table.
- Review both the function definition and all registrations/call sites before changing a signature.
- Never retry a callback with a different guessed signature after an error: its first invocation may already have produced a side effect.

Apply these conventions when touching the relevant code. They do not by themselves justify a broad refactor or a change to working addon behavior.

## Personal Assistant rule menus

PA's `Menu/ItemContextMenu.lua` builds Banking and Junk rules with `disabled` functions that close over the existing-rule flag and do not use mouse-row arguments. Rejecting every function-valued `disabled` field hides all of these actions.

The bridge has a narrow compatibility adapter for these five rule actions. It recognizes the localized parent and child labels through PA's StringIds, requires PA's `ItemContextMenu` module, and evaluates each recognized predicate once without inventing a mouse control. A predicate error skips the action without retrying. Disabled actions remain hidden and captured source entries are not mutated. Existing item-identity guards still protect action activation.

This exception does not enable arbitrary submenu evaluators, dynamic labels, checkbox evaluators or mouse-parent builders. A different addon, an unknown PA action or a changed PA callback contract requires separate source inspection before extending support. Label matching identifies this supported PA menu shape; it is not proof of callback ownership or a security boundary against other addons.

Keep both the positive PA cases and the unsupported-control cases in the regression suite. To exercise the actual installed PA builder, set `ESO_PA_SOURCE` to its `Menu/ItemContextMenu.lua` and run `lua5.1 scripts/tests/pa_integration.lua` (with `ESO_NATIVE_SOURCE` set to the pinned native checkout). The full runner also includes this integration when `ESO_PA_SOURCE` is set and reports an explicit skip otherwise. The integration covers inventory/bank rules, existing/new rules, TTC menu coexistence and replacement-item rejection.

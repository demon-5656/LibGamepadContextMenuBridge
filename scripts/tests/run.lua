-- Run from repository root: ESO_NATIVE_SOURCE=/path/to/esoui lua5.1 scripts/tests/run.lua lua5.1
-- Contract groups run in separate processes, so fixtures cannot borrow globals.
local interpreter = arg[1] or "lua5.1"
local source = arg[2] or "LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua"
assert(os.getenv("ESO_NATIVE_SOURCE"), "ESO_NATIVE_SOURCE must identify the pinned primary ESO source checkout")
assert(os.getenv("ESO_LCM_SOURCE"), "ESO_LCM_SOURCE must identify the LibCustomMenu 7.3.0 source file")
local function run(script, group)
    local command = string.format("%q %q %q", interpreter, script, source)
    if group then command = command .. " " .. string.format("%q", group) end
    local ok, reason, status = os.execute(command)
    assert(ok == true or ok == 0, command .. " failed: " .. tostring(reason or ok) .. " " .. tostring(status or ""))
end
run("scripts/tests/regression.lua")
local groups = {
    "identity", "menu-contracts", "capture-transaction", "native-state", "native-rebuild",
    "price-cache", "recipe-units", "overlay-owner", "overlay-retry", "overlay-expiry",
    "capture-setup", "live-registry", "native-clear", "native-death", "formatted-cache",
    "no-fake-mouse-controls", "unknown-result-link", "ttc-region", "registry-summary",
    "capture-identity", "junk-unmark", "native-context-policy", "material-setting", "native-cyclic-options", "native-recreated-action",
}
for _, group in ipairs(groups) do run("scripts/tests/contracts.lua", group) end
local integrations = {"lcm-keybind-lifecycle", "mixed-menu-clear", "tooltip-content-reuse", "nil-unique-id"}
for _, group in ipairs(integrations) do run("scripts/tests/core_integrations.lua", group) end
print("PASS isolated runner: regression + " .. #groups .. " contract groups + " .. #integrations .. " core integration groups")

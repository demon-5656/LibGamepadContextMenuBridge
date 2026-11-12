-- Focused regressions for final core review F1-F4. Each group runs isolated.
local selected = arg[2]
arg[2] = "helpers"
local h = dofile("scripts/tests/regression.lua")
arg[2] = selected
local check = h.check
local native = assert(os.getenv("ESO_NATIVE_SOURCE"), "set ESO_NATIVE_SOURCE")
local groups = 0
local function test(name, fn)
    if not selected or selected == name then
        fn()
        groups = groups + 1
        print("PASS core integration " .. name)
    end
end
local function fixture()
    local b = h.fresh()
    GetCVar = function() return "0" end
    zo_mixin = function(dest, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs(select(i, ...)) do dest[k] = v end
        end
    end
    dofile(native .. "/esoui/libraries/utility/baseobject.lua")
    dofile(native .. "/esoui/libraries/utility/zo_callbackobject.lua")
    dofile(native .. "/esoui/ingame/inventory/inventoryslotactions.lua")
    dofile(native .. "/esoui/libraries/utility/zo_hook.lua")
    if not unpack then unpack = table.unpack end
    ZO_ClearTable = function(t) for k in pairs(t) do t[k] = nil end end
    ZO_ClearNumericallyIndexedTable = function(t) for i = #t, 1, -1 do t[i] = nil end end
    IsUnitDead = function() return false end
    ZO_InventorySlot_GetType = function() return SLOT_TYPE_ITEM end
    local registry = ZO_CallbackObject:New()
    LibCustomMenu.CATEGORY_EARLY, LibCustomMenu.CATEGORY_LATE = 1, 1
    LibCustomMenu.contextMenuRegistry = registry
    b._buildNativeJunkAction = function() end
    return b, registry, ZO_InventorySlotActions:New(false), {bagId=BAG_BACKPACK, slotIndex=7}
end

test("lcm-keybind-lifecycle", function()
    for _, enabled in ipairs({false, true}) do
        local b, registry, a, slot = fixture()
        b.enabled = enabled
        SecurePostHook = ZO_PostHook -- C++ posthook adapter, same call order.
        local uiCalls, keyCalls, contextCalls, activations = 0, 0, 0, 0
        AddMenuItem = function() uiCalls = uiCalls + 1 end
        ZO_CreateStringId("SI_BASE", "Base")
        ZO_CreateStringId("SI_CONTEXT", "Context")
        ZO_CreateStringId("SI_KEY", "Key action")
        LibCustomMenu.keybindRegistry = ZO_CallbackObject:New()
        LibCustomMenu.enabledSpecialKeys = {}
        LibCustomMenu.keybindRegistry:RegisterCallback(2, function(_, sa)
            keyCalls = keyCalls + 1
            check(sa == a and not b._isCapturing, "LCM keybind lifecycle ran inside isolated context transaction")
            sa:GetSlotAction(1)[1] = "Live edit"
            sa:AddSlotAction(SI_KEY, function() activations = activations + 1 end, "keybind1")
        end)
        registry:RegisterCallback(1, function(_, sa)
            contextCalls = contextCalls + 1
            sa:AddSlotAction(SI_CONTEXT, function() end)
        end)
        ZO_InventorySlot_DiscoverSlotActionsFromActionList = function(_, sa)
            sa:AddSlotAction(SI_BASE, function() end, "primary")
        end
        local path = assert(os.getenv("ESO_LCM_SOURCE"), "ESO_LCM_SOURCE must identify the LibCustomMenu 7.3.0 source file")
        local file = assert(io.open(path, "r"))
        local text = file:read("*a"); file:close()
        local hook = assert(text:match("(local function HookContextMenu%(%)%s.-)\n%-%-%-%-%- Hook points for LibScrollableMenu"), "installed LCM HookContextMenu extraction failed")
        assert((loadstring or load)("local lib=LibCustomMenu\n" .. hook .. "\nHookContextMenu()", "@installed-LCM-HookContextMenu"))()
        b:_hookDiscoverSlotActions()
        ZO_InventorySlot_DiscoverSlotActionsFromActionList(slot, a)
        a:GetPrimaryActionName()
        check(keyCalls == 1 and contextCalls == (enabled and 1 or 0), "LCM builder replay or lost dispatch")
        check(a:GetKeybindActionName(1) == "Key action", "LCM live keybind action overwritten by facade merge")
        check(a.m_slotActions[1][1] == "Live edit", "LCM live row adjustment overwritten")
        check(#a.m_slotActions == (enabled and 3 or 2), "LCM live action row lost or duplicated")
        a:DoKeybindAction(1)
        check(activations == 1 and uiCalls == 0, "LCM action lost or mouse UI escaped capture")
        print("LCM_CONTROL enabled=" .. tostring(enabled) .. " keyBuilderCalls=" .. keyCalls .. " keybind=" .. a:GetKeybindActionName(1) .. " rows=" .. #a.m_slotActions)
    end
end)

test("mixed-menu-clear", function()
    for _, mode in ipairs({"native-clear", "global-clear", "native-emission-clear"}) do
        local b, registry, a, slot = fixture()
        local removed, replacement, uiCalls = 0, 0, 0
        local originalClear = function() uiCalls = uiCalls + 1 end
        ClearMenu = originalClear
        ZO_CreateStringId("SI_REMOVED", "Native removed")
        registry:RegisterCallback(1, function(_, sa)
            AddMenuItem("Removed before clear", function() removed = removed + 1 end)
            if mode == "native-emission-clear" then
                sa:AddSlotAction(SI_REMOVED, function() removed = removed + 1 end)
            end
            if mode == "native-clear" then sa:Clear() else ClearMenu() end
            AddMenuItem("Replacement", function() replacement = replacement + 1 end)
        end)
        local entries = b:_runContextCallbacks(LibCustomMenu, slot, a)
        check(#entries == 1 and entries[1].label == "Replacement", "virtual clear retained captured numeric entries: " .. mode)
        check(entries.identity and entries.nativeState and ClearMenu == originalClear, "clear destroyed transaction metadata/restoration")
        b:_appendEntriesToSlotActions(a, entries, slot)
        check(#a.m_slotActions == 1 and a.m_slotActions[1][1] == "Replacement", "cleared native menu emission resurrected: " .. mode)
        a.m_slotActions[1][2]()
        check(replacement == 1 and removed == 0 and uiCalls == 0, "cancelled callback or real mouse UI executed")
    end
end)

test("tooltip-content-reuse", function()
    for _, pending in ipairs({false, true}) do
        local b = h.fresh()
        local now, providerCalls, renders, positions = 1000, 0, 0, 0
        GetGameTimeMilliseconds = function() return now end
        b._isBoundItem = function() return false end
        GetItemLinkValue = function() return 1 end
        TamrielTradeCentrePrice = {GetPriceInfo=function() providerCalls=providerCalls+1;return {SuggestedPrice=10} end}
        local function control()
            return {IsControlHidden=function() return false end, IsHidden=function(self) return self.hidden end,
                GetWidth=function() return 500 end, GetHeight=function() return 600 end,
                SetHidden=function(self,v) self.hidden=v end, SetHandler=function(self,k,v) self[k]=v end}
        end
        local owner, window = control(), control()
        b._overlayWindow = {window=window, label={}}
        b._renderOverlayLines = function() renders = renders + 1 end
        b._resizeOverlayToText = function() end
        local anchorReady = not pending
        b._positionOverlay = function() positions=positions+1;return anchorReady end
        local tip = {ClearLines=function(self) self.content=nil end,
            LayoutBagItem=function(self) self.content="bag" end,
            LayoutQuestItem=function(self) self.content="quest" end}
        local containerTip = {tooltip=tip, ClearLines=function(self) self.tooltip:ClearLines() end, HasControls=function() return true end}
        dofile(native .. "/esoui/libraries/utility/zo_hook.lua")
        if not unpack then unpack=table.unpack end
        ZO_PostHookHandler = function() end
        dofile(native .. "/esoui/common/zo_tooltip/gamepad/zo_tooltip_gamepad.lua")
        local manager = setmetatable({GetTooltipContainer=function() return owner end,
            GetAndInitializeTooltipContainerTip=function() return containerTip end,
            SetBorderHidden=function() end, GetTooltipInfo=function() return {resetScroll=true} end,
            GetTooltipFragment=function() return {} end, DoesAutoShowTooltipBg=function() return false end}, ZO_GamepadTooltip.metaTable)
        GAMEPAD_TOOLTIPS = manager
        SCENE_MANAGER = {AddFragment=function() end, RemoveFragment=function() end}
        GetItemLink = function() return "|H1:item:123:|hOLD|h" end
        GetSlotStackSize = function() return 2 end
        GetItemSellValueWithBonuses = function() return 1 end
        local queued = {}
        zo_callLater = function(fn) queued[#queued+1] = fn end
        b:_hookTooltipPrice()
        manager:LayoutBagItem(GAMEPAD_LEFT_TOOLTIP, 1, 7)
        check(tip.content == "bag" and b._overlayRefresh and renders == 1, "bag model not established")
        check((#queued > 0) == pending, "pending retry fixture did not reach anchor failure")
        local generation = b._overlayGeneration
        manager:LayoutQuestItem(GAMEPAD_LEFT_TOOLTIP, 42)
        check(tip.content == "quest" and window.hidden and b._overlayGeneration > generation, "unsupported layout retained old bag overlay")
        check(not b._overlayRefresh and not b._overlayPriceExpiresAt and not b._overlayTooltipControl, "content reset retained model/TTL")
        local calls, attempts = providerCalls, positions
        now = now + 10000
        b:_refreshOverlayVisibility()
        for _, fn in ipairs(queued) do fn() end
        check(providerCalls == calls and positions == attempts and renders == 1 and window.hidden, "TTL/retry resurrected prior tooltip content")
        -- A supported layout after invalidation must still work, then direct reset cancels it.
        anchorReady = true
        manager:LayoutBagItem(GAMEPAD_LEFT_TOOLTIP, 1, 7)
        check(not window.hidden and b._overlayRefresh, "supported layout could not replace invalidated content")
        tip:ClearLines()
        check(window.hidden and not b._overlayRefresh, "direct content reset retained overlay")
    end
end)

test("nil-unique-id", function()
    for _, disappears in ipairs({false, true}) do
        local b, registry, a, slot = fixture()
        local id = disappears and "A" or nil
        local nilConversions, effects = 0, 0
        GetItemUniqueId = function() return id end
        Id64ToString = function(value)
            if value == nil then nilConversions = nilConversions + 1; return "0" end
            return value
        end
        registry:RegisterCallback(1, function()
            AddMenuItem("Guarded", function() effects = effects + 1 end)
        end)
        local entries = b:_runContextCallbacks(LibCustomMenu, slot, a)
        b:_appendEntriesToSlotActions(a, entries, slot)
        if disappears then
            check(#a.m_slotActions == 1, "valid initial item not captured")
            id = nil
            a.m_slotActions[1][2]()
        else
            check(entries.identity == nil and #a.m_slotActions == 0, "nil initial ID created executable action")
        end
        check(nilConversions == 0 and effects == 0, "nullable ID reached nonnullable converter or side effect")
    end
end)

assert(not selected or groups == 1, "unknown core integration group: " .. tostring(selected))
print("PASS " .. groups .. " core integration groups")

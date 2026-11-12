-- Deterministic control-flow tests with explicit ESO/TTC stubs, not an in-game test.
-- From the repository root: lua scripts/tests/regression.lua
local source = arg[1] or "LibGamepadContextMenuBridge/LibGamepadContextMenuBridge.lua"
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function fresh()
    LibGamepadContextMenuBridge = nil
    EVENT_MANAGER = { events = {}, updates = {} }
    function EVENT_MANAGER:RegisterForEvent(namespace, event, callback)
        self.events[event] = self.events[event] or {}
        self.events[event][namespace] = callback
    end
    function EVENT_MANAGER:UnregisterForEvent(namespace, event)
        if self.events[event] then self.events[event][namespace] = nil end
    end
    function EVENT_MANAGER:RegisterForUpdate(namespace, _, callback) self.updates[namespace] = callback end
    function EVENT_MANAGER:UnregisterForUpdate(namespace) self.updates[namespace] = nil end
    function EVENT_MANAGER:Fire(event, ...)
        local callbacks = {}
        for _, callback in pairs(self.events[event] or {}) do callbacks[#callbacks + 1] = callback end
        for _, callback in ipairs(callbacks) do callback(event, ...) end
    end
    function EVENT_MANAGER:Count(event)
        local count = 0
        for _ in pairs(self.events[event] or {}) do count = count + 1 end
        return count
    end
    EVENT_ADD_ON_LOADED = 1
    EVENT_PLAYER_ACTIVATED, EVENT_GAMEPAD_PREFERRED_MODE_CHANGED = 2, 3
    EVENT_OPEN_TRADING_HOUSE, EVENT_CLOSE_TRADING_HOUSE = 4, 5
    EVENT_CRAFTING_STATION_INTERACT, EVENT_END_CRAFTING_STATION_INTERACT = 6, 7
    BAG_BACKPACK, BAG_BANK, BAG_SUBSCRIBER_BANK, BAG_GUILDBANK, BAG_VIRTUAL = 1, 2, 3, 4, 5
    SLOT_TYPE_ITEM, SLOT_TYPE_BANK_ITEM, SLOT_TYPE_GUILD_BANK_ITEM = 10, 11, 12
    IsInGamepadPreferredMode = function() return true end
    INTERACTION_TRADINGHOUSE, CRAFTING_TYPE_INVALID = 77, 0
    GetInteractionType, GetCraftingInteractionType = function() return 0 end, function() return 0 end
    GetWorldName = function() return "EU Megaserver" end
    GetDisplayName = function() return "@fixture" end
    LibCustomMenu = { DIVIDER = "-" }
    MENU_ADD_OPTION_LABEL, MENU_ADD_OPTION_HEADER, MENU_ADD_OPTION_CHECKBOX = 1, 2, 3
    LINK_STYLE_DEFAULT = 0
    ITEM_LINK_TYPE = "item"
    SI_TOOLTIP_ITEM_NAME = "tooltip_item_name"
    GetLinkType = function(link)
        check(type(link) == "string", "GetLinkType requires a string")
        return link:match("|H%d+:([^:]+):") or ""
    end
    GetItemLinkItemId = function(link)
        check(type(link) == "string", "GetItemLinkItemId requires a string")
        return tonumber(link:match("|H%d+:item:(%d+):")) or 0
    end
    zo_strformat = function(format, value)
        if format == SI_TOOLTIP_ITEM_NAME then return (value:gsub("%^.*$", "")) end
        return value
    end
    ZO_Menu = {}
    GetTimeStamp = function() return 123456 end
    d = function() end
    zo_clamp = function(n, low, high) return math.max(low, math.min(n, high)) end
    local strings, nextId = {}, 0
    ZO_CreateStringId = function(name, value)
        nextId = nextId + 1
        _G[name], strings[nextId] = nextId, value
    end
    GetString = function(id) assert(strings[id], "unknown string ID"); return strings[id] end
    ZO_Inventory_GetBagAndIndex = function(slot) return slot.bagId, slot.slotIndex end
    TamrielTradeCentrePrice, LibAddonMenu2 = nil, nil
    dofile(source)
    return LibGamepadContextMenuBridge
end
local function contains(lines, value)
    for _, line in ipairs(lines) do
        if line:find(value, 1, true) then return true end
    end
    return false
end

-- 1. Both failing and successful action callbacks execute once, with no arguments.
do
    local b = fresh()
    b.debug = false
    local calls, argc = 0, nil
    local capture = { entries = {}, contextControl = {} }
    b:_captureMenuEntry(capture, "failure", function(...)
        calls, argc = calls + 1, select("#", ...)
        error("intentional action failure")
    end)
    local ok, err = pcall(capture.entries[1].callback)
    check(calls == 1 and argc == 0, "failed action replayed or got unexpected arguments")
    check(not ok and tostring(err):find("intentional action failure", 1, true), "action error hidden with debug disabled")
    b:_captureMenuEntry(capture, "success", function(...) argc = select("#", ...); calls = calls + 1 end)
    capture.entries[2].callback()
    check(calls == 2 and argc == 0, "successful action contract changed")
    print("PASS callbacks")
end

-- 2. Old timers cannot touch a new selection or resurrect hidden content.
do
    local b = fresh()
    local queue, rendered, ready = {}, {}, false
    local hidden, overlay = true, nil
    zo_callLater = function(fn, delay)
        check(delay == 40, "retry delay changed")
        queue[#queue + 1] = fn
    end
    overlay = { label = {}, window = {
        SetHidden = function(_, value) hidden = value end,
        SetHandler = function() end,
    } }
    b._overlayWindow = overlay
    b._ensureOverlayWindow = function() return overlay end
    b._buildCompactOverlayLines = function(_, lines) return lines end
    b._renderOverlayLines = function(_, _, lines) rendered[#rendered + 1] = lines[1] end
    b._resizeOverlayToText = function() end
    b._positionOverlay = function() return ready end
    local oldControl, newControl = {}, {}
    b:_showOverlayLines({ "|cFFFFFFOLD|r" }, "bag", oldControl)
    ready = true
    b:_showOverlayLines({ "|cFFFFFFNEW|r" }, "bag", newControl)
    local before = #rendered
    table.remove(queue, 1)()
    check(#rendered == before and b._overlayTooltipControl == newControl, "old retry replaced new selection")
    ready = false
    b:_showOverlayLines({ "|cFFFFFFHIDE|r" }, "bag", {})
    b:_hideOverlay()
    before = #rendered
    table.remove(queue, 1)()
    check(#rendered == before and hidden and b._overlaySource == nil, "old retry undid hide")
    b:_showOverlayLines({ "|cFFFFFFCURRENT|r" }, "bag", {})
    ready = true
    table.remove(queue, 1)()
    check(not hidden and rendered[#rendered]:find("CURRENT"), "current retry failed")
    ready = false
    b:_showOverlayLines({ "|cFFFFFFCAPPED|r" }, "bag", {})
    local retries = 0
    while #queue > 0 do
        retries = retries + 1
        check(retries <= 6, "retry cap exceeded")
        table.remove(queue, 1)()
    end
    check(retries == 6, "expected six retry attempts")
    print("PASS overlay lifecycle")
end

-- 3. Required LibCustomMenu dispatch: no duplicate cache or replay, even on failure.
do
    for _, outcome in ipairs({ "empty", "entry", "error", "partial-error" }) do
        local b = fresh()
        local runs = 0
        local marker = function() return "original menu" end
        AddMenuItem, AddCustomMenuItem = marker, marker
        AddCustomSubMenuItem, AddCustomMenuTooltip = marker, marker
        ShowMenu, ClearMenu = marker, marker
        local slotType = function() return 77 end
        ZO_InventorySlot_GetType = slotType
        b._resolveNormalizedSlotType = function(_, _, value) return value end
        local slot, actions = {}, { m_contextMenuMode = false }
        local builder = function(gotSlot, gotActions)
            runs = runs + 1
            check(gotSlot == slot and gotActions == actions, "builder args incorrect")
            check(gotActions.m_contextMenuMode == true, "context mode not set during capture")
            if outcome == "entry" or outcome == "partial-error" then AddCustomMenuItem("Action", function() end) end
            if outcome == "error" or outcome == "partial-error" then error("intentional builder failure") end
        end
        -- Shape and depth semantics from ZO_CallbackObject in API 101051.
        local registry = { callbackRegistry = { [1] = { { builder } } } }
        function registry:GetFireCallbackDepth() return self.fireCallbackDepth or 0 end
        function registry:Clean() end
        function registry:FireCallbacks(_, gotSlot, gotActions)
            self.fireCallbackDepth = self:GetFireCallbackDepth() + 1
            builder(gotSlot, gotActions)
            self.fireCallbackDepth = self:GetFireCallbackDepth() - 1
        end
        LibCustomMenu = { CATEGORY_EARLY = 1, CATEGORY_LATE = 1, contextMenuRegistry = registry, AddMenuItem = marker }
        local ok, result = pcall(function() return b:_runContextCallbacks(LibCustomMenu, slot, actions) end)
        check(runs == 1, "builder replayed")
        if outcome == "error" or outcome == "partial-error" then
            check(not ok and tostring(result):find("intentional builder failure", 1, true), "builder error hidden")
            check(tostring(result):find("stack traceback:", 1, true) and tostring(result):find("regression.lua", 1, true), "original builder traceback lost")
        else
            check(ok and #result == (outcome == "entry" and 1 or 0), "captured entries incorrect")
        end
        check(registry:GetFireCallbackDepth() == 0, "failed builder leaked callback depth")
        check(not b._isCapturing and actions.m_contextMenuMode == false, "capture state not restored")
        check(ZO_InventorySlot_GetType == slotType, "slot type global not restored")
        check(AddMenuItem == marker and AddCustomMenuItem == marker and AddCustomSubMenuItem == marker
            and AddCustomMenuTooltip == marker and ShowMenu == marker and ClearMenu == marker
            and LibCustomMenu.AddMenuItem == marker, "menu globals not restored")
    end
    print("PASS context dispatch")
end

-- 4. Flattened parent and child actions remain independent; checkboxes receive boolean state.
do
    local b = fresh()
    local function actionsFor(children, parent)
        local capture = { entries = {}, contextControl = {} }
        b:_captureSubMenuEntries(capture, "Parent", children, parent)
        local actions = { m_slotActions = {} }
        function actions:AddSlotAction(name, callback)
            self.m_slotActions[#self.m_slotActions + 1] = { GetString(name), callback }
        end
        b:_appendEntriesToSlotActions(actions, capture.entries, {})
        return actions.m_slotActions
    end
    local parents, children = 0, 0
    local rows = actionsFor({ { label = "Child", callback = function(...)
        check(select("#", ...) == 0, "child received context")
        children = children + 1
    end } }, function(...) check(select("#", ...) == 0, "parent received context"); parents = parents + 1 end)
    check(#rows == 2, "parent action lost")
    rows[2][2]()
    check(children == 1 and parents == 0, "child triggered parent")
    rows[1][2]()
    check(parents == 1 and children == 1, "parent triggered child")
    rows = actionsFor({ { label = "Child", callback = function() end } })
    check(#rows == 1, "unexpected synthetic parent action")
    rows = actionsFor({}, function() parents = parents + 1 end)
    check(#rows == 1, "parent-only submenu lost")
    rows[1][2]()
    check(parents == 2, "parent-only action not executable")
    for _, initial in ipairs({ false, true }) do
        local received, count
        rows = actionsFor({ { label = "Checkbox", itemType = MENU_ADD_OPTION_CHECKBOX,
            checked = function() return initial end,
            callback = function(...) count = select("#", ...); received = ... end } })
        check(#rows == 1, "checkbox entry lost")
        rows[1][2]()
        check(type(received) == "boolean" and received == not initial and count == 1,
            "checkbox must receive the new boolean state")
    end
    print("PASS submenu semantics")
end

-- 5. All ingredients are priced, but only eight detail rows are displayed.
do
    local b = fresh()
    local prices, ingredients = {}, {}
    b._collectRecipeIngredients = function() return ingredients end
    b._itemIdFromLink = function() return nil end
    b._getItemLinkQualityHex = function() return "FFFFFF" end
    b._formatCompactTooltipCurrency = function(_, n) return tostring(n) end
    b._getTtcPriceInfo = function(_, link) return prices[link] end
    local context = { recipeListIndex = 1, recipeIndex = 1 }
    local result = "|H1:item:999|hresult|h"
    for i = 1, 9 do
        local link = "|H1:item:" .. i .. "|hmat|h"
        ingredients[i] = { itemLink = link, name = "Material" .. i, quantity = 1 }
        prices[link] = { SuggestedPrice = 10 }
    end
    prices[result] = { SuggestedPrice = 200 }
    local lines = b:_buildCraftMaterialCostLines(result, context)
    check(contains(lines, "Mat total: 90"), "ninth ingredient omitted from total")
    check(contains(lines, "...and 1 more mats"), "hidden ingredient count incorrect")
    local displayed = 0
    for _, line in ipairs(lines) do if line:find("•", 1, true) then displayed = displayed + 1 end end
    check(displayed == 8, "detail rows exceed UI cap")
    -- Unknown price outside the visible rows must still invalidate the comparison.
    prices[ingredients[9].itemLink] = nil
    lines = b:_buildCraftMaterialCostLines(result, context)
    check(contains(lines, "partial (8/9 priced"), "partial estimate not labelled")
    check(not contains(lines, "vs crafted:") and not contains(lines, "Mat total:"), "partial estimate treated as complete")
    prices = { [result] = { SuggestedPrice = 200 } }
    lines = b:_buildCraftMaterialCostLines(result, context)
    check(contains(lines, "incomplete (no pricing)") and not contains(lines, "vs crafted:"), "missing-price estimate misleading")
    ingredients = { ingredients[1], ingredients[2] }
    prices[ingredients[1].itemLink], prices[ingredients[2].itemLink] = { SuggestedPrice = 10 }, { SuggestedPrice = 20 }
    ingredients[2].quantity = 2
    lines = b:_buildCraftMaterialCostLines(result, context)
    check(contains(lines, "Mat total: 50") and contains(lines, "vs crafted: +150"), "complete recipe calculation incorrect")
    print("PASS material estimates")
end
-- 6. Native recipe quantities and selected smithing quantity, never inventory stock.
do
    local b = fresh()
    local links = { "|H1:item:101|hmat|h", "|H1:item:102|hmat|h" }
    GetRecipeInfo = function(list, recipe)
        check(list == 2 and recipe == 3, "wrong recipe indices")
        return false, "Recipe", 2
    end
    GetRecipeIngredientItemLink = function(list, recipe, index)
        check(list == 2 and recipe == 3, "wrong ingredient indices")
        return links[index]
    end
    GetRecipeIngredientRequiredQuantity = function(_, _, index) return index == 1 and 3 or 5 end
    GetCurrentRecipeIngredientCount = function() error("owned counts are not required quantities") end
    GetRecipeNumIngredients = nil -- Not an API in 101051.
    GetItemLinkName = function(link) return link end
    local ingredients = b:_collectRecipeIngredients(2, 3)
    check(#ingredients == 2 and ingredients[1].quantity == 3 and ingredients[2].quantity == 5, "recipe count/quantity contract wrong")
    GetSmithingPatternMaterialItemLink = function(pattern, material, style)
        check(pattern == 7 and material == 2 and style == LINK_STYLE_DEFAULT, "wrong selected smithing material")
        return links[1]
    end
    GetSmithingPatternMaterialItemInfo = function() error("tier baseline must not replace selected quantity") end
    GetItemStyleMaterialLink = function(id) check(id == 11, "wrong style ID"); return "|H1:item:103|hstyle|h" end
    GetSmithingTraitItemLink = function(id) check(id == 4, "wrong trait index"); return "|H1:item:104|htrait|h" end
    ingredients = b:_collectSmithingPatternIngredients({patternIndex=7,materialIndex=2,materialQuantity=150,styleIndex=11,traitIndex=4})
    check(#ingredients == 3 and ingredients[1].quantity == 150 and ingredients[2].quantity == 1 and ingredients[3].quantity == 1, "smithing recipe omitted selected quantity/style/trait")
    check(#b:_collectSmithingPatternIngredients({patternIndex=7,materialIndex=2}) == 0, "missing quantity fabricated")
    print("PASS native crafting contracts")
end

-- 7. Trading prices belong only to the selected lot, not a similar item.
do
    local b = fresh()
    local link = "|H1:item:501|hitem|h"
    local selected = { itemLink=link, stackCount=20, sellerName="A", purchasePrice=1234 }
    -- Native BrowseResults inherits ZO_SortFilterList:GetSelectedData().
    GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS = { GetSelectedData = function() return selected end }
    GetTradingHouseSearchResultItemInfo = function() error("must not scan other lots") end
    local price, count = b:_lookupTradingHouseListingPrice(link,20,"A")
    check(price == 1234 and count == 20,"selected lot price missing")
    check(b:_lookupTradingHouseListingPrice(link,20,"B") == nil,"price crossed seller boundary")
    check(b:_lookupTradingHouseListingPrice(link,10,"A") == nil,"price crossed stack boundary")
    check(b:_lookupTradingHouseListingPrice("|H1:item:502|hitem|h",20,"A") == nil,"price crossed item boundary")
    selected.isGuildSpecificItem, selected.slotIndex = true, 9
    GetGuildSpecificItemLink = function(index) check(index == 9,"wrong guild-specific lot"); return "|H1:collectible:501|hitem|h" end
    check(b:_lookupTradingHouseListingPrice("|H1:collectible:501|hitem|h",20,"A") == 1234,"guild-specific listing lost")
    GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS = nil
    check(b:_lookupTradingHouseListingPrice(link,20,"A") == nil,"absent UI should return no listing")
    print("PASS exact Trading House lot")
end

-- 8. Optional addons stay optional; the verified TTC colon contract is used once.
do
    local b = fresh()
    check(b:_getTtcPriceInfo("|H1:item:1|hitem|h") == nil,"TTC unexpectedly required")
    b:_initializeSettingsPanel()
    check(not b._settingsPanelRegistered,"settings registered without optional LAM")
    local calls, provider = 0, nil
    provider = { GetPriceInfo = function(self, link)
        check(self == provider and link == "|H1:item:1|hitem|h","TTC calling convention changed")
        calls = calls + 1
        return { Avg=15, SuggestedPrice=12 }
    end }
    TamrielTradeCentrePrice = provider
    check(b:_getTtcPriceInfo("|H1:item:1|hitem|h").SuggestedPrice == 12 and calls == 1,"TTC price lost or provider replayed")
    provider.GetPriceInfo = function() calls=calls+1;error("provider failure") end
    check(not pcall(function() b:_getTtcPriceInfo("|H1:item:1|hitem|h") end) and calls == 2,"provider errors masked or retried")
    print("PASS optional dependencies")
end
-- 9. Hook actual gamepad classes and per-tooltip targets; no guessed instance globals.
do
    local b = fresh()
    local hookCounts = {}
    local function installHook(target, method, hook)
        check(type(target[method]) == "function", "hook target is not a verified fixture method: " .. method)
        hookCounts[target] = hookCounts[target] or {}
        hookCounts[target][method] = (hookCounts[target][method] or 0) + 1
        local original = target[method]
        target[method] = function(self, ...)
            local result = original(self, ...)
            hook(self, ...)
            return result
        end
    end
    SecurePostHook = function(target, method, hook)
        assert(type(target) == "table", "bad argument #1 to 'SecurePostHook' (table expected, got " .. type(target) .. ")")
        installHook(target, method, hook)
    end
    ZO_PostHook = installHook
    ZO_PostHookHandler = function(target, event, hook)
        target.handlers[event] = hook
    end
    local function tooltip()
        -- ESO native controls are userdata, not Lua tables.
        local control, meta
        if newproxy then
            control = newproxy(true)
            meta = getmetatable(control)
        else
            -- Newer Lua has no newproxy: use a closed read-only file as userdata.
            control = assert(io.open(source, "r"))
            control:close()
            meta = {}
            debug.setmetatable(control, meta)
        end
        local fields = { handlers={}, LayoutBagItem=function() return "bag result" end,
            LayoutGuildStoreSearchResult=function() return "store result" end }
        meta.__index, meta.__newindex = fields, fields
        return control
    end
    GAMEPAD_LEFT_TOOLTIP, GAMEPAD_RIGHT_TOOLTIP, GAMEPAD_MOVABLE_TOOLTIP = 11, 12, 13
    local left, right, movable = tooltip(), tooltip(), tooltip()
    local pool = { [11]=left, [13]=movable }
    GAMEPAD_TOOLTIPS = { GetTooltip=function(_, kind) return pool[kind] end }
    check(not b:_hookTooltipPrice(), "partial tooltip installation reported complete")
    pool[12] = right
    check(b:_hookTooltipPrice(), "late tooltip was not hooked")
    check(hookCounts[left].LayoutBagItem == 1 and hookCounts[right].LayoutBagItem == 1, "existing target hooked twice")
    local bagCalls = 0
    b._appendGamepadTooltipInfo = function(_, tip, bag, slot)
        check(tip == left and bag == 1 and slot == 8, "bag hook forwarded wrong parameters")
        bagCalls = bagCalls + 1
    end
    check(type(left) == "userdata", "tooltip fixture no longer models a native control")
    check(left:LayoutBagItem(1, 8) == "bag result", "post-hook lost original layout return")
    check(bagCalls == 1,"bag overlay not called exactly once")
    local storeCalls = 0
    b._lookupTradingHouseListingPrice = function(_, link, count, seller)
        check(link == "|H1:item:704|hlisting|h" and count == 4 and seller == "seller", "store hook lost listing identity")
        return 80, 4
    end
    b._appendGamepadTooltipInfoByLink = function(_, tip, link, count, price, sourceName)
        check(tip == right and count == 4 and price == 80 and sourceName == "guildstore", "store hook forwarded wrong context")
        storeCalls = storeCalls + 1
    end
    check(b:_hookTradingHouseTooltip(), "native Trading House tooltip was not hooked")
    check(b:_hookTradingHouseTooltip(), "Trading House hook retry failed")
    check(right:LayoutGuildStoreSearchResult("|H1:item:704|hlisting|h", 4, "seller") == "store result", "store post-hook lost original return")
    check(storeCalls == 1 and hookCounts[right].LayoutGuildStoreSearchResult == 1, "store hook duplicated or missing")
    b._overlayTooltipControl = right
    left.handlers.OnEffectivelyHidden(left)
    check(b._overlayTooltipControl == right,"unrelated tooltip hide invalidated current overlay")
    right.handlers.OnEffectivelyHidden(right)
    check(b._overlayTooltipControl == nil,"owner tooltip hide left overlay alive")
    ZO_GamepadSmithingCreation = {SetupResultTooltip=function() end}
    ZO_GamepadProvisioner = {RefreshRecipeDetails=function() end}
    ZO_GamepadAlchemy = {UpdateTooltip=function() end}
    ZO_GamepadEnchanting = {UpdateTooltip=function() end}
    SMITHING, GAMEPAD_SMITHING = nil, nil -- Not owners of these result-tooltip instances.
    local shown = {}
    b._appendGamepadTooltipInfoByLink = function(_, tip, link, _, _, sourceName, context)
        shown[#shown + 1] = {tip=tip,link=link,source=sourceName,context=context}
    end
    GetSmithingPatternResultLink = function(pattern, material, quantity, style, trait, linkStyle)
        check(pattern == 3 and material == 2 and quantity == 150 and style == 11 and trait == 4 and linkStyle == LINK_STYLE_DEFAULT,
            "smithing hook altered selected parameters")
        return "|H1:item:700|hresult|h"
    end
    GetRecipeResultItemLink = function(list, recipe, linkStyle)
        check(list == 2 and recipe == 3 and linkStyle == LINK_STYLE_DEFAULT,"provisioner hook altered recipe indices")
        return "|H1:item:701|hresult|h"
    end
    local function resultControl() return {tip={},IsControlHidden=function() return false end} end
    local smithing = { resultTooltip=resultControl() }
    local provisioner = { resultTooltip=resultControl() }
    check(b:_hookCraftingTooltips(),"gamepad crafting hooks not installed")
    ZO_GamepadSmithingCreation.SetupResultTooltip(smithing,3,2,150,11,4)
    check(#shown == 1 and shown[1].tip == smithing.resultTooltip.tip and shown[1].context.materialQuantity == 150
        and shown[1].context.forceSmithingPatternMaterials,"smithing hook lost its real tooltip/quantity")
    ZO_GamepadProvisioner.RefreshRecipeDetails(provisioner,{recipeListIndex=2,recipeIndex=3})
    check(#shown == 2 and shown[2].tip == provisioner.resultTooltip.tip and shown[2].context.recipeIndex == 3,
        "provisioner hook guessed recipe/tooltip instead of native selectedData")
    ZO_GamepadProvisioner.RefreshRecipeDetails(provisioner,nil)
    check(not b._templateCraftingOverlayActive,"cleared recipe selection kept crafting overlay active")
    local alchemy = {tooltip=resultControl(),IsCraftable=function() return true end,GetResultItemLink=function() return "|H1:item:702|hpotion|h" end}
    local enchanting = {resultTooltip=resultControl(),IsCraftable=function() return true end,GetResultItemLink=function() return "|H1:item:703|hglyph|h" end}
    ZO_GamepadAlchemy.UpdateTooltip(alchemy)
    ZO_GamepadEnchanting.UpdateTooltip(enchanting)
    check(#shown == 4 and shown[3].tip == alchemy.tooltip.tip and shown[4].tip == enchanting.resultTooltip.tip,
        "alchemy/enchanting hook used a keyboard class or arbitrary tooltip pool")
    b:_hookCraftingTooltips()
    check(hookCounts[ZO_GamepadSmithingCreation].SetupResultTooltip == 1,"crafting class hooked twice")
    print("PASS gamepad hook contracts")
end

-- 10. Late-UI retries are coalesced and bounded; disabled overlays cannot render.
do
    local b = fresh()
    local queue = {}
    b._hookTooltipPrice = function() return false end
    b._hookCraftingTooltips = function() return false end
    b._hookTradingHouseTooltip = function() return false end
    EVENT_MANAGER.RegisterForUpdate = function(self, namespace, delay, fn)
        check(delay == 2500,"wrong hook retry delay")
        self.updates[namespace] = fn
        queue[#queue+1] = fn
    end
    b:_scheduleTooltipPriceHookRetry()
    b:_scheduleTooltipPriceHookRetry()
    check(#queue == 1,"duplicate hook retry scheduled")
    local attempts = 0
    while #queue > 0 do
        attempts=attempts+1
        check(attempts <= 6,"unbounded hook retry")
        table.remove(queue,1)()
    end
    check(attempts == 6 and not b._tooltipHookRetryScheduled,"hook retry cap/state incorrect")
    b.enabled = false
    b._ensureOverlayWindow = function() error("disabled overlay tried to create/render a window") end
    b:_showOverlayLines({"disabled"},"bag",{})
    check(b._overlayTooltipControl == nil,"disabled overlay changed target")
    print("PASS bounded UI readiness")
end
-- 11. Server profiles inherit legacy settings once, without sharing nested tables.
do
    local name = "LibGamepadContextMenuBridge_SavedVars"
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end
    ZO_DeepTableCopy = copy
    ZO_SavedVars = { NewAccountWide = function(_, key, version, namespace, defaults, profile)
        check(key == name and version == 1 and namespace == nil and profile ~= nil, "wrong server saved-vars contract")
        local raw = _G[key] or {}
        _G[key] = raw
        raw[profile] = raw[profile] or {}
        local account = raw[profile][GetDisplayName()] or {}
        raw[profile][GetDisplayName()] = account
        local saved = account["$AccountWide"] or { version = version }
        account["$AccountWide"] = saved
        for field, value in pairs(defaults) do if saved[field] == nil then saved[field] = copy(value) end end
        return saved
    end }
    local source = os.getenv("ESO_SAVEDVARS_SOURCE")
    if source then
        ZO_ClearTable = function(t) for key in pairs(t) do t[key] = nil end end
        dofile(source)
    end
    local legacy = { version=1, enabled=true, showTtcPriceInTooltip=false, debugLog={"legacy log"} }
    _G[name] = { Default = { ["@fixture"] = { ["$AccountWide"] = legacy } } }
    local eu = fresh()
    eu:_initializeSavedVars()
    check(eu.enabled and eu.savedVars.showTtcPriceInTooltip == false, "legacy settings were lost")
    eu:SetEnabled(false)
    eu.savedVars.debugLog[1] = "EU only"
    local na = fresh()
    GetWorldName = function() return "NA Megaserver" end
    na:_initializeSavedVars()
    check(na.enabled and na.savedVars.debugLog[1] == "legacy log", "EU settings leaked into NA")
    check(legacy.enabled == true and legacy.debugLog[1] == "legacy log", "migration modified legacy data")
    local again = fresh()
    again:_initializeSavedVars()
    check(not again.enabled and again.savedVars.debugLog[1] == "EU only", "existing server profile overwritten on reload")
    local slot = {bagId=BAG_SUBSCRIBER_BANK,slotIndex=2}
    check(again:_resolveNormalizedSlotType(slot,99) == SLOT_TYPE_BANK_ITEM,"bank lookup mapping lost")
    slot.bagId = 99
    check(again:_resolveNormalizedSlotType(slot,99) == 99,"unknown bag lost original slot type")
    _G[name] = nil
    local clean = fresh()
    clean:_initializeSavedVars()
    check(clean.enabled and clean.savedVars.debug == false, "clean install lost defaults")
    check(_G[name]["EU Megaserver"]["@fixture"]["$AccountWide"] ~= nil and _G[name].Default == nil,"clean install created a legacy profile")
    print("PASS server settings migration")
end

-- 12. Addon load does not install UI hooks; close events and retries live only while needed.
do
    local b = fresh()
    local gamepad = false
    IsInGamepadPreferredMode = function() return gamepad end
    local installs = {}
    for _, pair in ipairs({{"_hookDiscoverSlotActions","_discoverHooked"},{"_hookRefreshKeybindStrip","_refreshHooked"},
        {"_hookTooltipPrice","_tooltipPriceHooked"},{"_hookCraftingTooltips","_craftingTooltipsHooked"},{"_hookTradingHouseTooltip","_tradingHouseTooltipHooked"}}) do
        local method, flag = pair[1], pair[2]
        b[method] = function(self)
            if not self[flag] then installs[method]=(installs[method] or 0)+1;self[flag]=true end
            return true
        end
    end
    b._initializeSavedVars = function(self) self.savedVars={enabled=true,showTtcPriceInTooltip=true,showJunkStatusInTooltip=true,showVendorPriceInTooltip=true} end
    b._initializeSlashCommands, b._initializeSettingsPanel = function() end, function() end
    EVENT_MANAGER:Fire(EVENT_ADD_ON_LOADED,"LibGamepadContextMenuBridge")
    check(next(installs) == nil and next(EVENT_MANAGER.updates) == nil,"addon load eagerly installed hooks/updaters")
    EVENT_MANAGER:Fire(EVENT_PLAYER_ACTIVATED)
    check(next(installs) == nil and EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 0,"keyboard mode installed gamepad hooks")
    gamepad = true
    EVENT_MANAGER:Fire(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED,true)
    check(installs._hookDiscoverSlotActions == 1 and installs._hookCraftingTooltips == 1,"first gamepad use did not install hooks")
    check(EVENT_MANAGER:Count(EVENT_CLOSE_TRADING_HOUSE) == 0 and EVENT_MANAGER:Count(EVENT_END_CRAFTING_STATION_INTERACT) == 0,"idle close events registered")
    EVENT_MANAGER:Fire(EVENT_OPEN_TRADING_HOUSE)
    check(EVENT_MANAGER:Count(EVENT_CLOSE_TRADING_HOUSE) == 1,"store close not registered on open")
    EVENT_MANAGER:Fire(EVENT_CLOSE_TRADING_HOUSE)
    check(EVENT_MANAGER:Count(EVENT_CLOSE_TRADING_HOUSE) == 0,"store close listener survived close")
    EVENT_MANAGER:Fire(EVENT_CRAFTING_STATION_INTERACT)
    check(b._craftingStationActive and EVENT_MANAGER:Count(EVENT_END_CRAFTING_STATION_INTERACT) == 1,"crafting lifecycle did not start")
    EVENT_MANAGER:Fire(EVENT_END_CRAFTING_STATION_INTERACT)
    check(not b._craftingStationActive and EVENT_MANAGER:Count(EVENT_END_CRAFTING_STATION_INTERACT) == 0,"crafting lifecycle did not stop")
    b:SetShowTtcPriceInTooltip(false);b:SetShowJunkStatusInTooltip(false);b:SetShowVendorPriceInTooltip(false)
    check(EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 0 and EVENT_MANAGER:Count(EVENT_CRAFTING_STATION_INTERACT) == 0,"disabled overlay retained context events")
    b:SetShowTtcPriceInTooltip(true)
    check(EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 1,"overlay events not restored")
    b:SetEnabled(false)
    check(EVENT_MANAGER:Count(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED) == 0 and EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 0,"disabled bridge retained runtime events")
    GetCraftingInteractionType = function() return 1 end
    b:SetEnabled(true)
    check(installs._hookDiscoverSlotActions == 1 and EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 1,"re-enable duplicated hooks or lost events")
    check(b._craftingStationActive and EVENT_MANAGER:Count(EVENT_END_CRAFTING_STATION_INTERACT) == 1,"re-enable at open station lost close listener")
    EVENT_MANAGER:Fire(EVENT_END_CRAFTING_STATION_INTERACT)
    GetCraftingInteractionType = function() return 0 end
    b:SetEnabled(false)
    GetInteractionType = function() return INTERACTION_TRADINGHOUSE end
    b:SetEnabled(true)
    check(EVENT_MANAGER:Count(EVENT_CLOSE_TRADING_HOUSE) == 1,"re-enable inside store lost close listener")
    EVENT_MANAGER:Fire(EVENT_CLOSE_TRADING_HOUSE)
    GetInteractionType = function() return 0 end
    b._tooltipPriceHooked = false
    b:_scheduleTooltipPriceHookRetry()
    local retry = EVENT_MANAGER.updates.LibGamepadContextMenuBridge_TooltipHookRetry
    check(retry ~= nil,"missing retry updater")
    gamepad = false
    EVENT_MANAGER:Fire(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED,false)
    check(next(EVENT_MANAGER.updates) == nil and EVENT_MANAGER:Count(EVENT_CRAFTING_STATION_INTERACT) == 0,"keyboard switch retained updater/events")
    retry()
    check(not b._tooltipPriceHooked,"cancelled retry installed stale hooks")
    local disabled = fresh()
    disabled.enabled = false
    disabled._initializeSavedVars, disabled._initializeSlashCommands, disabled._initializeSettingsPanel = function() end, function() end, function() end
    EVENT_MANAGER:Fire(EVENT_ADD_ON_LOADED,"LibGamepadContextMenuBridge")
    check(EVENT_MANAGER:Count(EVENT_PLAYER_ACTIVATED) == 0 and EVENT_MANAGER:Count(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED) == 0
        and EVENT_MANAGER:Count(EVENT_OPEN_TRADING_HOUSE) == 0 and next(EVENT_MANAGER.updates) == nil,"disabled startup registered runtime work")
    print("PASS deferred gamepad lifecycle")
end
-- 13. Native link APIs handle only strings/items; item names use the ESO formatter.
do
    local b = fresh()
    check(b:_getItemLinkQualityHex(nil) == "B8B29A", "nil item link reached native API")
    check(b:_getItemLinkQualityHex("|H1:collectible:42:|hTest|h") == "B8B29A", "non-item link treated as item")
    check(#b:_collectRecipeIngredientsByResultLink(nil) == 0, "nil result reached native item parser")
    check(#b:_collectRecipeIngredientsByResultLink("|H1:item:0:|h|h") == 0, "zero item ID queried as recipe")
    local recipeCalls = 0
    GetRecipeInfoFromItemId = function(id)
        check(id == 731,"native item ID not used")
        recipeCalls = recipeCalls + 1
        return 1,2,3
    end
    b._collectRecipeIngredients = function(_, list, recipe)
        check(list == 2 and recipe == 3,"native recipe indices lost")
        return {{ itemLink="|H1:item:9:|hOre|h",quantity=1,name="Ore^ns" }}
    end
    check(#b:_collectRecipeIngredientsByResultLink("|H1:item:731:|hResult|h") == 1 and recipeCalls == 1,"recipe ID lookup not exactly once")
    b._getItemLinkQualityHex = function() return "FFFFFF" end
    b._getTtcPriceInfo = function() return {SuggestedPrice=1} end
    b._formatCompactTooltipCurrency = function(_, value) return tostring(value) end
    local lines = b:_buildCraftMaterialCostLines("|H1:item:731:|hResult|h",{recipeListIndex=2,recipeIndex=3})
    local text = table.concat(lines,"\n")
    check(text:find("Ore x1",1,true) and not text:find("^",1,true),"item name bypassed native grammar formatter")
    print("PASS native item-link helpers")
end
print("PASS all 13 regression groups (" .. checks .. " assertions)")

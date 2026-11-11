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
    EVENT_MANAGER = { RegisterForEvent = function() end }
    EVENT_ADD_ON_LOADED = 1
    MENU_ADD_OPTION_LABEL, MENU_ADD_OPTION_HEADER, MENU_ADD_OPTION_CHECKBOX = 1, 2, 3
    ZO_Menu = {}
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
    b.debug = true
    local calls, argc = 0, nil
    local capture = { entries = {}, contextControl = {} }
    b:_captureMenuEntry(capture, "failure", function(...)
        calls, argc = calls + 1, select("#", ...)
        error("intentional action failure")
    end)
    capture.entries[1].callback()
    check(calls == 1 and argc == 0, "failed action replayed or got unexpected arguments")
    check(contains(b._debugLog, "intentional action failure"), "callback error not logged")
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

-- 3. Exercise the real capture/restore path with FireCallbacks and the cache fallback.
do
    for _, useFire in ipairs({ true, false }) do
        for _, outcome in ipairs({ "empty", "entry", "error" }) do
            local b = fresh()
            local runs, rawRuns = 0, 0
            local marker = function() return "original menu" end
            AddMenuItem, AddCustomMenuItem = marker, marker
            AddCustomSubMenuItem, AddCustomMenuTooltip = marker, marker
            ShowMenu, ClearMenu = marker, marker
            local slotType = function() return 77 end
            ZO_InventorySlot_GetType = slotType
            b._resolveNormalizedSlotType = function(_, _, value) return value end
            b._invokeRawRegistryHandlers = function() rawRuns = rawRuns + 1 end
            local slot, actions = {}, { m_contextMenuMode = false }
            local builder = function(gotSlot, gotActions)
                runs = runs + 1
                check(gotSlot == slot and gotActions == actions, "builder args incorrect")
                check(gotActions.m_contextMenuMode == true, "context mode not set during capture")
                if outcome == "error" then error("intentional builder failure") end
                if outcome == "entry" then AddCustomMenuItem("Action", function() end) end
            end
            local registry = { callbackRegistry = { [1] = { { builder } } } }
            if useFire then
                registry.FireCallbacks = function(_, _, gotSlot, gotActions) builder(gotSlot, gotActions) end
            else
                b:_rememberContextCallback(builder, 1, {})
            end
            LibCustomMenu = { CATEGORY_EARLY = 1, CATEGORY_LATE = 1, contextMenuRegistry = registry }
            local entries = b:_runContextCallbacks(LibCustomMenu, slot, actions)
            check(runs == 1 and rawRuns == 0, "builder replayed")
            check(#entries == (outcome == "entry" and 1 or 0), "captured entries incorrect")
            check(not b._isCapturing and actions.m_contextMenuMode == false, "capture state not restored")
            check(ZO_InventorySlot_GetType == slotType, "slot type global not restored")
            check(AddMenuItem == marker and AddCustomMenuItem == marker and AddCustomSubMenuItem == marker
                and AddCustomMenuTooltip == marker and ShowMenu == marker and ClearMenu == marker,
                "menu globals not restored")
        end
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
            self.m_slotActions[#self.m_slotActions + 1] = { name = name, callback = callback }
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
    rows[2].callback()
    check(children == 1 and parents == 0, "child triggered parent")
    rows[1].callback()
    check(parents == 1 and children == 1, "parent triggered child")
    rows = actionsFor({ { label = "Child", callback = function() end } })
    check(#rows == 1, "unexpected synthetic parent action")
    rows = actionsFor({}, function() parents = parents + 1 end)
    check(#rows == 1, "parent-only submenu lost")
    rows[1].callback()
    check(parents == 2, "parent-only action not executable")
    for _, initial in ipairs({ false, true }) do
        local received, count
        rows = actionsFor({ { label = "Checkbox", itemType = MENU_ADD_OPTION_CHECKBOX,
            checked = function() return initial end,
            callback = function(...) count = select("#", ...); received = ... end } })
        check(#rows == 1, "checkbox entry lost")
        rows[1].callback()
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
print("PASS all 5 regression groups (" .. checks .. " assertions)")

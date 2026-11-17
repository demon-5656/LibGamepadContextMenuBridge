-- Run with ESO_NATIVE_SOURCE and ESO_PA_SOURCE (PA's Menu/ItemContextMenu.lua).
-- Execute the installed PA builder, not a rewritten copy of its predicates.
local selected = arg[2]
arg[2] = "helpers"
local h = dofile("scripts/tests/regression.lua")
arg[2] = selected
local check = h.check
local native = assert(os.getenv("ESO_NATIVE_SOURCE"), "set ESO_NATIVE_SOURCE")
local paSource = assert(os.getenv("ESO_PA_SOURCE"), "set ESO_PA_SOURCE to PA's Menu/ItemContextMenu.lua")
local cases = 0
for _, bag in ipairs({1, 2}) do
    for _, existing in ipairs({false, true}) do
        for _, stale in ipairs({false, true}) do
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
            IsUnitDead = function() return false end
            local registry = ZO_CallbackObject:New()
            LibCustomMenu.CATEGORY_EARLY, LibCustomMenu.CATEGORY_LATE = 1, 1
            LibCustomMenu.contextMenuRegistry = registry
            function LibCustomMenu:RegisterContextMenu(callback) registry:RegisterCallback(1, callback) end
            ZO_InventorySlot_GetType = function() return bag == 1 and SLOT_TYPE_ITEM or SLOT_TYPE_BANK_ITEM end
            local id, sideEffects, ttcCalls = "original", 0, 0
            GetItemUniqueId = function() return id end
            local link = "|H1:item:123:|hTest item|h"
            GetItemLink = function() return link end
            ITEMTYPE_RACIAL_STYLE_MOTIF, ITEMTYPE_RECIPE, ITEMTYPE_MASTER_WRIT, ITEMTYPE_AVA_REPAIR = 2, 3, 4, 5
            GetItemType = function() return 1 end
            b._buildNativeJunkAction = function() end
            local names = {"SI_PA_SUBMENU_PAB", "SI_PA_SUBMENU_PAJ", "SI_PA_SUBMENU_PAB_ADD_RULE",
                "SI_PA_SUBMENU_PAB_EDIT_RULE", "SI_PA_SUBMENU_PAB_DELETE_RULE",
                "SI_PA_SUBMENU_PAJ_MARK_PERM_JUNK", "SI_PA_SUBMENU_PAJ_UNMARK_PERM_JUNK"}
            for _, name in ipairs(names) do ZO_CreateStringId(name, "Localized " .. name) end
            local function effect(value)
                check(value == link, "PA callback received the wrong item")
                sideEffects = sideEffects + 1
            end
            PersonalAssistant = {
                HelperFunctions = {
                    getPAItemLinkIdentifier = function(value) check(value == link, "wrong PA item link"); return "123" end,
                    isKeyInTable = function(t, key) return t[key] ~= nil end,
                    isItemLinkCharacterBound = function() return false end,
                    CanItemBeMarkedAsJunkExt = function() return true end,
                },
                ProfileManager = {
                    PABanking = {hasActiveProfile=function() return true end},
                    PAJunk = {hasActiveProfile=function() return true end},
                },
                Banking = {SavedVars={Custom={customItemsEnabled=true, PAItemIds=existing and {["123"]={}} or {}}}},
                Junk = {SavedVars={Custom={customItemsEnabled=true, PAItemIds=existing and {["123"]=true} or {}}},
                    Custom={addItemLinkToPermanentJunk=effect, removeItemLinkFromPermanentJunk=effect}},
                CustomDialogs = {
                    initPABAddCustomRuleUIDialog=function() end,
                    showPABAddCustomRuleUIDIalog=effect, deletePABCustomRule=effect,
                },
            }
            dofile(paSource)
            PersonalAssistant.ItemContextMenu.initHooksOnInventoryContextMenu(LibCustomMenu)
            registry:RegisterCallback(1, function()
                AddCustomSubMenuItem("TTC", {{label="Search", callback=function() ttcCalls=ttcCalls+1 end}})
            end)
            local slot = {bagId=bag, slotIndex=7}
            local actions = ZO_InventorySlotActions:New(false)
            local entries = b:_runContextCallbacks(LibCustomMenu, slot, actions)
            check(#entries == 3, "real PA Banking/Junk or TTC menu missing")
            check(#entries[1].entries == (existing and 2 or 1), "real PA Banking disabled predicates lost")
            check(#entries[2].entries == 1, "real PA Junk disabled predicates lost")
            check(entries[2].entries[1].label == GetString(existing and SI_PA_SUBMENU_PAJ_UNMARK_PERM_JUNK or SI_PA_SUBMENU_PAJ_MARK_PERM_JUNK), "wrong real PA Junk rule")
            check(sideEffects == 0 and ttcCalls == 0, "menu build executed an action")
            b:_appendEntriesToSlotActions(actions, entries, slot)
            check(#actions.m_slotActions == (existing and 4 or 3), "flattened PA/TTC actions missing or duplicated")
            if stale then id = "replacement" end
            for _, action in ipairs(actions.m_slotActions) do action[2]() end
            check(sideEffects == (stale and 0 or (existing and 3 or 2)), "real PA callbacks lost, replayed or applied to a replacement item")
            check(ttcCalls == (stale and 0 or 1), "TTC coexistence or identity guard changed")
            cases = cases + 1
        end
    end
end
print("PASS installed PA integration: " .. cases .. " inventory/bank, existing/new rule and identity cases")

local MAJOR = "LibGamepadContextMenuBridge"
local MINOR = 3
local ADDON_VERSION = "1.4.1"

local existing = _G[MAJOR]
if existing and existing.minor and existing.minor >= MINOR then
    return
end

local bridge = existing or {}
_G[MAJOR] = bridge

bridge.major = MAJOR
bridge.minor = MINOR
bridge.enabled = true
bridge.debug = bridge.debug or false
bridge._initialized = false
bridge._registerWrapped = false
bridge._discoverHooked = false
bridge._refreshHooked = false
bridge._contextCallbacks = bridge._contextCallbacks or {}
bridge._callbackKeys = bridge._callbackKeys or {}
bridge._submenuDialogRegistered = bridge._submenuDialogRegistered or false
bridge._submenuDialogName = bridge._submenuDialogName or (MAJOR .. "_SubmenuDialog")
bridge._settingsPanelRegistered = bridge._settingsPanelRegistered or false
bridge._slashCommandsRegistered = bridge._slashCommandsRegistered or false
bridge._tooltipPriceHooked = bridge._tooltipPriceHooked or false
bridge._playerActivatedHookRegistered = bridge._playerActivatedHookRegistered or false
bridge._debugLog = bridge._debugLog or {}
bridge._stringIdByLabel = bridge._stringIdByLabel or {}
bridge._nextStringIdIndex = bridge._nextStringIdIndex or 1

local SAVED_VARS_NAME = MAJOR .. "_SavedVars"
local SAVED_VARS_VERSION = 1
local DEFAULTS = {
    enabled = true,
    debug = false,
    debugVerbose = false,
    debugToChat = true,
    debugStoreHistory = true,
    maxDebugMessages = 200,
    showTtcPriceInTooltip = false,
    showTtcPriceDetailsInTooltip = false,
    showJunkStatusInTooltip = true,
    showVendorPriceInTooltip = true,
    showBoundStatusInTooltip = true,
}

local unpackArgs = unpack or table.unpack

local function TrimString(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetDebugTimestamp()
    if type(GetTimeStamp) == "function" then
        local ok, ts = pcall(GetTimeStamp)
        if ok and ts then
            return tostring(ts)
        end
    end
    return tostring(math.floor((GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or 0) / 1000))
end

function bridge:_addDebugHistory(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    self._debugLog[#self._debugLog + 1] = string.format("%s %s", GetDebugTimestamp(), message)

    local limit = DEFAULTS.maxDebugMessages
    if self.savedVars and tonumber(self.savedVars.maxDebugMessages) then
        limit = math.max(20, tonumber(self.savedVars.maxDebugMessages))
    end

    while #self._debugLog > limit do
        table.remove(self._debugLog, 1)
    end
end

function bridge:_debugMessage(message, verboseOnly)
    if not self.debug then
        return
    end

    if verboseOnly and not self.debugVerbose then
        return
    end

    local formatted = string.format("[%s] %s", MAJOR, tostring(message))

    if not self.savedVars or self.savedVars.debugStoreHistory ~= false then
        self:_addDebugHistory(formatted)
    end

    if (not self.savedVars or self.savedVars.debugToChat ~= false) and type(d) == "function" then
        d(formatted)
    end
end

local function LogDebug(message)
    bridge:_debugMessage(message, false)
end

local function LogTrace(message)
    bridge:_debugMessage(message, true)
end

local function SafeCallCallback(callback)
    if type(callback) ~= "function" then
        return
    end

    local ok = pcall(callback)
    if ok then
        return
    end

    pcall(callback, nil)
end

local function SafeCallCallbackWithContext(callback, contextControl)
    if type(callback) ~= "function" then
        return
    end

    local ok = pcall(callback, contextControl)
    if ok then
        return
    end

    SafeCallCallback(callback)
end

local function EvaluateValue(value, ...)
    if type(value) ~= "function" then
        return value
    end

    local ok, result = pcall(value, ...)
    if ok then
        return result
    end

    ok, result = pcall(value)
    if ok then
        return result
    end

    return nil
end

local function SafeGetString(stringId, fallback)
    if type(GetString) == "function" and stringId ~= nil then
        local ok, value = pcall(GetString, stringId)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    return fallback or ""
end

local function SafeGetTargetData(entryList)
    if not entryList or type(entryList.GetTargetData) ~= "function" then
        return nil
    end

    local ok, data = pcall(entryList.GetTargetData, entryList)
    if ok then
        return data
    end

    ok, data = pcall(entryList.GetTargetData)
    if ok then
        return data
    end

    return nil
end

local function ResolveCategory(lcm, category)
    local early = lcm and tonumber(lcm.CATEGORY_EARLY) or nil
    local late = lcm and tonumber(lcm.CATEGORY_LATE) or nil

    category = tonumber(category) or late or early

    if category == nil then
        return nil
    end

    if early == nil or late == nil then
        return category
    end

    if type(zo_clamp) == "function" then
        return zo_clamp(category, early, late)
    end

    if category < early then
        return early
    end

    if category > late then
        return late
    end

    return category
end

local function ResolveLabel(value, contextControl)
    value = EvaluateValue(value, ZO_Menu, contextControl)

    if value == nil then
        return nil
    end

    if type(value) == "number" and type(GetString) == "function" then
        local ok, localized = pcall(GetString, value)
        if ok and type(localized) == "string" and localized ~= "" then
            return localized
        end
    end

    if type(value) ~= "string" then
        value = tostring(value)
    end

    if value == "" then
        return nil
    end

    return value
end

local function IsDividerLabel(label)
    if not label then
        return true
    end

    if label == "-" then
        return true
    end

    if type(LibCustomMenu) == "table" and label == LibCustomMenu.DIVIDER then
        return true
    end

    return false
end

local function BuildCallbackKey(func, category, args)
    local key = tostring(func) .. "|" .. tostring(category)
    if args and #args > 0 then
        for i = 1, #args do
            key = key .. "|" .. tostring(args[i])
        end
    end
    return key
end

local function ReadActionName(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local actionName = entry.name or entry.actionName or entry[1]

    if type(actionName) == "number" and type(GetString) == "function" then
        local ok, localized = pcall(GetString, actionName)
        if ok and type(localized) == "string" then
            actionName = localized
        end
    end

    if type(actionName) ~= "string" or actionName == "" then
        return nil
    end

    return actionName
end

local function CollectExistingActionNames(slotActions)
    local names = {}

    local candidates = {
        slotActions and slotActions.m_slotActions,
        slotActions and slotActions.m_actionList,
        slotActions and slotActions.actionList,
        slotActions and slotActions.m_actions,
    }

    for i = 1, #candidates do
        local list = candidates[i]
        if type(list) == "table" then
            for index = 1, #list do
                local name = ReadActionName(list[index])
                if name then
                    names[name] = true
                end
            end
        end
    end

    return names
end

local function StampActionLabel(slotActions, label, callback)
    if type(slotActions) ~= "table" or type(label) ~= "string" or label == "" or type(callback) ~= "function" then
        return
    end

    local candidates = {
        slotActions.m_slotActions,
        slotActions.m_actionList,
        slotActions.actionList,
        slotActions.m_actions,
    }

    for i = 1, #candidates do
        local list = candidates[i]
        if type(list) == "table" then
            for index = #list, 1, -1 do
                local actionEntry = list[index]
                if type(actionEntry) == "table" then
                    local entryCallback = actionEntry.callback or actionEntry.actionCallback or actionEntry[2]
                    if entryCallback == callback then
                        actionEntry.name = actionEntry.name or label
                        actionEntry.actionName = actionEntry.actionName or label
                        if actionEntry[1] == nil then
                            actionEntry[1] = label
                        end
                        return
                    end
                end
            end
        end
    end
end

function bridge:_ensureActionStringId(label)
    if type(label) ~= "string" or label == "" then
        return label
    end

    local existingId = self._stringIdByLabel[label]
    if existingId ~= nil then
        return existingId
    end

    if type(ZO_CreateStringId) ~= "function" then
        return label
    end

    local idName = string.format("SI_LGCMB_ACTION_%d", tonumber(self._nextStringIdIndex or 1))
    self._nextStringIdIndex = (self._nextStringIdIndex or 1) + 1
    pcall(ZO_CreateStringId, idName, label)

    local createdId = _G[idName]
    if createdId == nil then
        createdId = label
    end

    self._stringIdByLabel[label] = createdId
    return createdId
end

function bridge:_readContextMenuRegistry()
    local lcm = LibCustomMenu
    if type(lcm) ~= "table" then
        return nil, "LibCustomMenu missing"
    end

    local registry = lcm.contextMenuRegistry
    if type(registry) ~= "table" then
        return nil, "contextMenuRegistry missing"
    end

    local callbackRegistry = registry.callbackRegistry or registry.m_callbackRegistry
    if type(callbackRegistry) ~= "table" then
        return nil, "callback registry missing"
    end

    return callbackRegistry, nil
end

function bridge:_summarizeContextRegistry()
    local callbackRegistry, err = self:_readContextMenuRegistry()
    if not callbackRegistry then
        return err or "unavailable", 0
    end

    local early = LibCustomMenu and tonumber(LibCustomMenu.CATEGORY_EARLY) or nil
    local late = LibCustomMenu and tonumber(LibCustomMenu.CATEGORY_LATE) or nil
    if early == nil or late == nil then
        return "category bounds unavailable", 0
    end
    local parts = {}
    local total = 0
    for category = early, late do
        local handlers = callbackRegistry[category]
        local count = type(handlers) == "table" and #handlers or 0
        total = total + count
        parts[#parts + 1] = string.format("%d=%d", category, count)
    end

    return table.concat(parts, ", "), total
end

function bridge:_invokeRawRegistryHandlers(lcm, inventorySlot, slotActions)
    local callbackRegistry, err = self:_readContextMenuRegistry()
    if not callbackRegistry then
        LogTrace("Raw registry fallback unavailable: " .. tostring(err))
        return 0
    end

    local early = tonumber(lcm.CATEGORY_EARLY)
    local late = tonumber(lcm.CATEGORY_LATE)
    if early == nil or late == nil then
        return 0
    end
    local invoked = 0

    for category = early, late do
        local handlers = callbackRegistry[category]
        if type(handlers) == "table" then
            for i = 1, #handlers do
                local entry = handlers[i]
                local callback = nil
                local args = nil

                if type(entry) == "function" then
                    callback = entry
                elseif type(entry) == "table" then
                    callback = entry.callback or entry.func or entry[1]
                    if type(entry.args) == "table" then
                        args = entry.args
                    end
                end

                if type(callback) == "function" then
                    local ok, callbackErr
                    if args and #args > 0 then
                        local callArgs = {}
                        for argIndex = 1, #args do
                            callArgs[#callArgs + 1] = args[argIndex]
                        end
                        callArgs[#callArgs + 1] = inventorySlot
                        callArgs[#callArgs + 1] = slotActions
                        ok, callbackErr = pcall(callback, unpackArgs(callArgs))
                    else
                        ok, callbackErr = pcall(callback, inventorySlot, slotActions)
                    end

                    invoked = invoked + 1
                    if not ok then
                        LogTrace(string.format("Raw handler error in category %s: %s", tostring(category), tostring(callbackErr)))
                    end
                end
            end
        end
    end

    return invoked
end

function bridge:_resolveNormalizedSlotType(inventorySlot, slotType)
    if slotType == SLOT_TYPE_ITEM or slotType == SLOT_TYPE_BANK_ITEM or slotType == SLOT_TYPE_GUILD_BANK_ITEM then
        return slotType
    end

    if type(ZO_Inventory_GetBagAndIndex) ~= "function" then
        return slotType
    end

    local bagId, slotIndex = ZO_Inventory_GetBagAndIndex(inventorySlot)
    if bagId == nil or slotIndex == nil then
        return slotType
    end

    if type(BAG_BACKPACK) == "number" and bagId == BAG_BACKPACK and SLOT_TYPE_ITEM ~= nil then
        return SLOT_TYPE_ITEM
    end

    if type(BAG_BANK) == "number" and bagId == BAG_BANK and SLOT_TYPE_BANK_ITEM ~= nil then
        return SLOT_TYPE_BANK_ITEM
    end

    if type(BAG_SUBSCRIBER_BANK) == "number" and bagId == BAG_SUBSCRIBER_BANK and SLOT_TYPE_BANK_ITEM ~= nil then
        return SLOT_TYPE_BANK_ITEM
    end

    if type(BAG_GUILDBANK) == "number" and bagId == BAG_GUILDBANK and SLOT_TYPE_GUILD_BANK_ITEM ~= nil then
        return SLOT_TYPE_GUILD_BANK_ITEM
    end

    return slotType
end

function bridge:_resolveBagAndSlot(inventorySlot)
    if type(inventorySlot) == "table" then
        local bagId = inventorySlot.bagId or inventorySlot.bag
        local slotIndex = inventorySlot.slotIndex or inventorySlot.slot
        if bagId ~= nil and slotIndex ~= nil then
            return bagId, slotIndex
        end
    end

    if type(ZO_Inventory_GetBagAndIndex) ~= "function" then
        return nil, nil
    end

    local bagId, slotIndex = ZO_Inventory_GetBagAndIndex(inventorySlot)
    if bagId == nil or slotIndex == nil then
        return nil, nil
    end

    return bagId, slotIndex
end

function bridge:_buildNativeJunkAction(inventorySlot)
    if type(SetItemIsJunk) ~= "function" or type(IsItemJunk) ~= "function" then
        return nil
    end

    local bagId, slotIndex = self:_resolveBagAndSlot(inventorySlot)
    if bagId == nil or slotIndex == nil then
        return nil
    end

    if type(BAG_VIRTUAL) == "number" and bagId == BAG_VIRTUAL then
        return nil
    end

    local isJunk = IsItemJunk(bagId, slotIndex) == true
    if not isJunk then
        if type(IsItemPlayerLocked) == "function" and IsItemPlayerLocked(bagId, slotIndex) then
            return nil
        end

        if type(CanItemBeMarkedAsJunk) ~= "function" or not CanItemBeMarkedAsJunk(bagId, slotIndex) then
            return nil
        end
    end

    local labelStringId = isJunk and SI_ITEM_ACTION_UNMARK_AS_JUNK or SI_ITEM_ACTION_MARK_AS_JUNK
    local fallbackLabel = isJunk and "Unmark as Junk" or "Mark as Junk"
    local label = SafeGetString(labelStringId, fallbackLabel)
    if type(label) ~= "string" or label == "" then
        return nil
    end

    return {
        label = label,
        callback = function()
            SetItemIsJunk(bagId, slotIndex, not isJunk)
        end,
    }
end

function bridge:_rememberContextCallback(func, category, args)
    if type(func) ~= "function" then
        return
    end

    local key = BuildCallbackKey(func, category, args)
    if self._callbackKeys[key] then
        return
    end

    self._callbackKeys[key] = true

    local callbacks = self._contextCallbacks[category]
    if not callbacks then
        callbacks = {}
        self._contextCallbacks[category] = callbacks
    end

    callbacks[#callbacks + 1] = {
        func = func,
        args = args,
    }

    self._callbackCountLast = (self._callbackCountLast or 0) + 1
    LogTrace(string.format("Registered callback in category %s (total=%d)", tostring(category), self._callbackCountLast))
end

function bridge:_importExistingCallbacks(lcm)
    local registry = lcm and lcm.contextMenuRegistry
    if type(registry) ~= "table" then
        return
    end

    local callbackRegistry = registry.callbackRegistry or registry.m_callbackRegistry
    if type(callbackRegistry) ~= "table" then
        return
    end

    for category, handlers in pairs(callbackRegistry) do
        local numericCategory = tonumber(category)
        if numericCategory and type(handlers) == "table" then
            local resolvedCategory = ResolveCategory(lcm, numericCategory)

            for i = 1, #handlers do
                local entry = handlers[i]
                if type(entry) == "table" then
                    local callback = entry[1] or entry.callback
                    if type(callback) == "function" then
                        local args = {}
                        if entry.args and type(entry.args) == "table" then
                            for argIndex = 1, #entry.args do
                                args[#args + 1] = entry.args[argIndex]
                            end
                        else
                            for argIndex = 2, #entry do
                                args[#args + 1] = entry[argIndex]
                            end
                        end

                        self:_rememberContextCallback(callback, resolvedCategory, args)
                    end
                end
            end
        end
    end
end

function bridge:_wrapRegisterContextMenu(lcm)
    if self._registerWrapped then
        return
    end

    if type(lcm) ~= "table" or type(lcm.RegisterContextMenu) ~= "function" then
        return
    end

    self._originalRegisterContextMenu = lcm.RegisterContextMenu

    lcm.RegisterContextMenu = function(libSelf, func, category, ...)
        local callbackArgs = { ... }
        bridge:_rememberContextCallback(func, ResolveCategory(lcm, category), callbackArgs)
        return bridge._originalRegisterContextMenu(libSelf, func, category, ...)
    end

    self._registerWrapped = true
end

function bridge:RegisterContextMenu(func, category, ...)
    local lcm = LibCustomMenu
    if type(lcm) ~= "table" then
        return
    end

    if type(lcm.RegisterContextMenu) == "function" then
        lcm:RegisterContextMenu(func, category, ...)
    else
        self:_rememberContextCallback(func, ResolveCategory(lcm, category), { ... })
    end
end

function bridge:SetEnabled(enabled)
    self.enabled = not not enabled
    if self.savedVars then
        self.savedVars.enabled = self.enabled
    end
    LogDebug("Bridge enabled: " .. tostring(self.enabled))
end

function bridge:SetDebugEnabled(enabled)
    self.debug = not not enabled
    if self.savedVars then
        self.savedVars.debug = self.debug
    end
    self:_debugMessage("Debug enabled: " .. tostring(self.debug), false)
end

function bridge:SetDebugVerbose(enabled)
    self.debugVerbose = not not enabled
    if self.savedVars then
        self.savedVars.debugVerbose = self.debugVerbose
    end
    self:_debugMessage("Debug verbose: " .. tostring(self.debugVerbose), false)
end

function bridge:SetShowTtcPriceInTooltip(enabled)
    local value = not not enabled
    if self.savedVars then
        self.savedVars.showTtcPriceInTooltip = value
    end
end

function bridge:SetShowTtcPriceDetailsInTooltip(enabled)
    local value = not not enabled
    if self.savedVars then
        self.savedVars.showTtcPriceDetailsInTooltip = value
    end
end

function bridge:SetShowJunkStatusInTooltip(enabled)
    local value = not not enabled
    if self.savedVars then
        self.savedVars.showJunkStatusInTooltip = value
    end
end

function bridge:SetShowVendorPriceInTooltip(enabled)
    local value = not not enabled
    if self.savedVars then
        self.savedVars.showVendorPriceInTooltip = value
    end
end

function bridge:SetShowBoundStatusInTooltip(enabled)
    local value = not not enabled
    if self.savedVars then
        self.savedVars.showBoundStatusInTooltip = value
    end
end

function bridge:ClearDebugLog()
    self._debugLog = {}
    self:_debugMessage("Debug log cleared", false)
end

function bridge:DumpDebugLog(limit)
    if type(d) ~= "function" then
        return
    end

    local count = #self._debugLog
    if count == 0 then
        d(string.format("[%s] Debug log is empty", MAJOR))
        return
    end

    local maxLines = tonumber(limit) or 40
    if maxLines < 1 then
        maxLines = 1
    end

    local startIndex = math.max(1, count - maxLines + 1)
    d(string.format("[%s] Debug log (%d entries, showing %d..%d)", MAJOR, count, startIndex, count))
    for i = startIndex, count do
        d(self._debugLog[i])
    end
end

function bridge:_initializeSavedVars()
    if self.savedVars then
        return
    end

    if type(ZO_SavedVars) ~= "table" or type(ZO_SavedVars.NewAccountWide) ~= "function" then
        self.enabled = DEFAULTS.enabled
        self.debug = DEFAULTS.debug
        self.debugVerbose = DEFAULTS.debugVerbose
        return
    end

    self.savedVars = ZO_SavedVars:NewAccountWide(SAVED_VARS_NAME, SAVED_VARS_VERSION, nil, DEFAULTS)
    self.enabled = self.savedVars.enabled ~= false
    self.debug = self.savedVars.debug == true
    self.debugVerbose = self.savedVars.debugVerbose == true
    LogTrace("SavedVars loaded")
end

function bridge:_shouldShowTtcTooltipPrice()
    return self.savedVars and self.savedVars.showTtcPriceInTooltip == true
end

function bridge:_shouldShowTtcTooltipDetails()
    return self.savedVars and self.savedVars.showTtcPriceDetailsInTooltip == true
end

function bridge:_shouldShowJunkStatusInTooltip()
    return not not (self.savedVars and self.savedVars.showJunkStatusInTooltip ~= false)
end

function bridge:_shouldShowVendorPriceInTooltip()
    return not not (self.savedVars and self.savedVars.showVendorPriceInTooltip ~= false)
end

function bridge:_shouldShowBoundStatusInTooltip()
    return not not (self.savedVars and self.savedVars.showBoundStatusInTooltip ~= false)
end

function bridge:_getTtcPriceInfo(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local providers = {
        _G.TamrielTradeCentrePrice,
        type(TamrielTradeCentre) == "table" and TamrielTradeCentre.Price or nil,
    }

    for i = 1, #providers do
        local provider = providers[i]
        if type(provider) == "table" and type(provider.GetPriceInfo) == "function" then
            local ok, priceInfo = pcall(provider.GetPriceInfo, provider, itemLink)
            if ok and type(priceInfo) == "table" then
                return {
                    Avg = priceInfo.Avg or priceInfo.A,
                    Max = priceInfo.Max or priceInfo.X,
                    Min = priceInfo.Min or priceInfo.N,
                    EntryCount = priceInfo.EntryCount or priceInfo.EC,
                    AmountCount = priceInfo.AmountCount or priceInfo.AC,
                    SuggestedPrice = priceInfo.SuggestedPrice or priceInfo.S,
                    SaleAvg = priceInfo.SaleAvg or priceInfo.SA,
                    SaleEntryCount = priceInfo.SaleEntryCount or priceInfo.SE,
                    SaleAmountCount = priceInfo.SaleAmountCount or priceInfo.SAC,
                }
            end
        end
    end

    return nil
end

function bridge:_getTtcPriceTableUpdatedText()
    local providers = {
        _G.TamrielTradeCentrePrice,
        type(TamrielTradeCentre) == "table" and TamrielTradeCentre.Price or nil,
    }

    for i = 1, #providers do
        local provider = providers[i]
        if type(provider) == "table" and type(provider.GetPriceTableUpdatedDateString) == "function" then
            local ok, updatedText = pcall(provider.GetPriceTableUpdatedDateString, provider)
            if ok and type(updatedText) == "string" and updatedText ~= "" then
                return updatedText
            end
        end
    end

    return nil
end

function bridge:_formatTtcCurrency(value)
    if type(value) ~= "number" then
        return nil
    end

    if type(ZO_CurrencyControl_FormatCurrency) == "function" then
        local ok, formatted = pcall(ZO_CurrencyControl_FormatCurrency, value, true, nil)
        if ok and type(formatted) == "string" and formatted ~= "" then
            return formatted
        end
    end

    if type(TamrielTradeCentre) == "table" and type(TamrielTradeCentre.FormatNumber) == "function" then
        local ok, formatted = pcall(TamrielTradeCentre.FormatNumber, TamrielTradeCentre, value, 0)
        if ok and type(formatted) == "string" and formatted ~= "" then
            return formatted
        end
    end

    return tostring(zo_floor and zo_floor(value) or math.floor(value))
end

function bridge:_formatTooltipInfoCurrency(value)
    return self:_formatTtcCurrency(value)
end

function bridge:_getItemLinkFromBagAndSlot(bagId, slotIndex)
    if type(GetItemLink) ~= "function" or bagId == nil or slotIndex == nil then
        return nil
    end

    local ok, itemLink = pcall(GetItemLink, bagId, slotIndex)
    if not ok or type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    return itemLink
end

function bridge:_getVendorPriceText(bagId, slotIndex)
    if not self:_shouldShowVendorPriceInTooltip() then
        return nil
    end

    local sellPrice = nil
    if type(GetItemSellValueWithBonuses) == "function" then
        local ok, value = pcall(GetItemSellValueWithBonuses, bagId, slotIndex)
        if ok and type(value) == "number" then
            sellPrice = value
        end
    end

    if sellPrice == nil and type(GetItemSellValue) == "function" then
        local ok, value = pcall(GetItemSellValue, bagId, slotIndex)
        if ok and type(value) == "number" then
            sellPrice = value
        end
    end

    if type(sellPrice) ~= "number" or sellPrice <= 0 then
        return nil
    end

    local priceText = self:_formatTooltipInfoCurrency(sellPrice)
    if type(priceText) ~= "string" or priceText == "" then
        return nil
    end

    return "Vendor: " .. priceText
end

function bridge:_getJunkStatusText(bagId, slotIndex)
    if not self:_shouldShowJunkStatusInTooltip() then
        return nil
    end

    if type(IsItemJunk) ~= "function" then
        return nil
    end

    local ok, isJunk = pcall(IsItemJunk, bagId, slotIndex)
    if ok and isJunk == true then
        return "Junk: Yes"
    end

    if type(CanItemBeMarkedAsJunk) == "function" then
        local canMarkOk, canMark = pcall(CanItemBeMarkedAsJunk, bagId, slotIndex)
        if canMarkOk and canMark == true then
            return "Junk: No"
        end
    end

    return nil
end

function bridge:_getBoundStatusText(bagId, slotIndex, itemLink)
    if not self:_shouldShowBoundStatusInTooltip() then
        return nil
    end

    local isBound = false
    if type(IsItemBound) == "function" then
        local ok, value = pcall(IsItemBound, bagId, slotIndex)
        if ok and value == true then
            isBound = true
        end
    end

    if not isBound and type(IsItemLinkBound) == "function" and type(itemLink) == "string" then
        local ok, value = pcall(IsItemLinkBound, itemLink)
        if ok and value == true then
            isBound = true
        end
    end

    return isBound and "Bound: Yes" or nil
end

function bridge:_buildTooltipInfoLines(bagId, slotIndex)
    local lines = {}
    local itemLink = self:_getItemLinkFromBagAndSlot(bagId, slotIndex)

    if self:_shouldShowTtcTooltipPrice() and itemLink then
        local priceInfo = self:_getTtcPriceInfo(itemLink)
        if type(priceInfo) == "table" then
            local primaryPrice = priceInfo.SuggestedPrice or priceInfo.Avg or priceInfo.Min
            local primaryPriceText = self:_formatTooltipInfoCurrency(primaryPrice)
            if type(primaryPriceText) == "string" and primaryPriceText ~= "" then
                lines[#lines + 1] = "TTC: " .. primaryPriceText
            end

            if self:_shouldShowTtcTooltipDetails() then
                local minPriceText = self:_formatTooltipInfoCurrency(priceInfo.Min or primaryPrice)
                local avgPriceText = self:_formatTooltipInfoCurrency(priceInfo.Avg or primaryPrice)
                local maxPriceText = self:_formatTooltipInfoCurrency(priceInfo.Max or primaryPrice)
                if minPriceText and avgPriceText and maxPriceText then
                    lines[#lines + 1] = string.format("Min: %s  Avg: %s  Max: %s", minPriceText, avgPriceText, maxPriceText)
                end

                local listings = tonumber(priceInfo.EntryCount or 0) or 0
                local listedItems = tonumber(priceInfo.AmountCount or listings) or listings
                if listings > 0 then
                    if listedItems ~= listings then
                        lines[#lines + 1] = string.format("Listings: %d  Items: %d", listings, listedItems)
                    else
                        lines[#lines + 1] = string.format("Listings: %d", listings)
                    end
                end

                local saleAvgText = self:_formatTooltipInfoCurrency(priceInfo.SaleAvg)
                if saleAvgText then
                    lines[#lines + 1] = "Sale Avg: " .. saleAvgText
                end

                local sales = tonumber(priceInfo.SaleEntryCount or 0) or 0
                local soldItems = tonumber(priceInfo.SaleAmountCount or sales) or sales
                if sales > 0 then
                    if soldItems ~= sales then
                        lines[#lines + 1] = string.format("Sales: %d  Items: %d", sales, soldItems)
                    else
                        lines[#lines + 1] = string.format("Sales: %d", sales)
                    end
                end

                local updatedText = self:_getTtcPriceTableUpdatedText()
                if updatedText then
                    lines[#lines + 1] = updatedText
                end
            end
        end
    end

    local junkStatus = self:_getJunkStatusText(bagId, slotIndex)
    if junkStatus then
        lines[#lines + 1] = junkStatus
    end

    local boundStatus = self:_getBoundStatusText(bagId, slotIndex, itemLink)
    if boundStatus then
        lines[#lines + 1] = boundStatus
    end

    local vendorPrice = self:_getVendorPriceText(bagId, slotIndex)
    if vendorPrice then
        lines[#lines + 1] = vendorPrice
    end

    return lines
end

function bridge:_appendGamepadTooltipInfo(tooltip, bagId, slotIndex)
    if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then
        return
    end

    local lines = self:_buildTooltipInfoLines(bagId, slotIndex)
    if #lines == 0 then
        return
    end

    local style = nil
    if type(ZO_TOOLTIP_STYLES) == "table" then
        style = ZO_TOOLTIP_STYLES.bodyDescription or ZO_TOOLTIP_STYLES.tooltipDefault
    end

    for i = 1, #lines do
        if style ~= nil then
            tooltip:AddLine(lines[i], style)
        else
            tooltip:AddLine(lines[i])
        end
    end

    if style ~= nil then
        tooltip:AddLine(" ", style)
    else
        tooltip:AddLine(" ")
    end
end

function bridge:_hookTooltipPrice()
    if self._tooltipPriceHooked then
        return true
    end

    if type(GAMEPAD_TOOLTIPS) ~= "table" or type(GAMEPAD_TOOLTIPS.GetTooltip) ~= "function" then
        return false
    end

    local tooltipTypes = {
        GAMEPAD_LEFT_TOOLTIP,
        GAMEPAD_RIGHT_TOOLTIP,
        GAMEPAD_MOVABLE_TOOLTIP,
    }

    local hookedAny = false
    for i = 1, #tooltipTypes do
        local tooltipType = tooltipTypes[i]
        local tooltip = GAMEPAD_TOOLTIPS:GetTooltip(tooltipType)
        if type(tooltip) == "table" and type(tooltip.LayoutBagItem) == "function" and not tooltip._lgcmbTooltipWrapped then
            local base = tooltip.LayoutBagItem
            tooltip.LayoutBagItem = function(control, bagId, slotIndex, ...)
                local result1, result2, result3, result4, result5, result6 = base(control, bagId, slotIndex, ...)
                bridge:_appendGamepadTooltipInfo(control, bagId, slotIndex)
                return result1, result2, result3, result4, result5, result6
            end
            tooltip._lgcmbTooltipWrapped = true
            hookedAny = true
        end
    end

    if hookedAny then
        self._tooltipPriceHooked = true
        LogTrace("Tooltip info hook registered")
        return true
    end

    return false
end

function bridge:_scheduleTooltipPriceHookRetry()
    if self._tooltipPriceHooked then
        return
    end

    if type(zo_callLater) == "function" then
        zo_callLater(function()
            bridge:_hookTooltipPrice()
        end, 1500)
    end
end

function bridge:_initializeSlashCommands()
    if self._slashCommandsRegistered then
        return
    end

    if type(SLASH_COMMANDS) ~= "table" then
        return
    end

    local function PrintHelp()
        if type(d) ~= "function" then
            return
        end
        d(string.format("[%s] /lgcmb status", MAJOR))
        d(string.format("[%s] /lgcmb on|off", MAJOR))
        d(string.format("[%s] /lgcmb debug on|off", MAJOR))
        d(string.format("[%s] /lgcmb verbose on|off", MAJOR))
        d(string.format("[%s] /lgcmb log [count]", MAJOR))
        d(string.format("[%s] /lgcmb clearlog", MAJOR))
    end

    SLASH_COMMANDS["/lgcmb"] = function(text)
        local cmd = string.lower(TrimString(text or ""))
        if cmd == "" or cmd == "help" then
            PrintHelp()
            return
        end

        if cmd == "status" then
            if type(d) == "function" then
                local summary, total = self:_summarizeContextRegistry()
                d(string.format("[%s] enabled=%s debug=%s verbose=%s callbacks=%d",
                    MAJOR,
                    tostring(self.enabled),
                    tostring(self.debug),
                    tostring(self.debugVerbose),
                    tonumber(self._callbackCountLast or 0)))
                d(string.format("[%s] context registry total=%d (%s)", MAJOR, tonumber(total or 0), tostring(summary)))
            end
            return
        end

        if cmd == "on" then
            self:SetEnabled(true)
            return
        end
        if cmd == "off" then
            self:SetEnabled(false)
            return
        end
        if cmd == "debug on" then
            self:SetDebugEnabled(true)
            return
        end
        if cmd == "debug off" then
            self:SetDebugEnabled(false)
            return
        end
        if cmd == "verbose on" then
            self:SetDebugVerbose(true)
            return
        end
        if cmd == "verbose off" then
            self:SetDebugVerbose(false)
            return
        end
        if cmd == "clearlog" then
            self:ClearDebugLog()
            return
        end

        local logCount = cmd:match("^log%s+(%d+)$")
        if cmd == "log" or logCount then
            self:DumpDebugLog(tonumber(logCount) or 40)
            return
        end

        PrintHelp()
    end

    self._slashCommandsRegistered = true
    LogTrace("Slash command /lgcmb registered")
end

function bridge:_initializeSettingsPanel()
    if self._settingsPanelRegistered then
        return
    end

    local lam = _G.LibAddonMenu2 or _G.LibAddonMenu
    if type(lam) ~= "table" then
        return
    end
    if type(lam.RegisterAddonPanel) ~= "function" or type(lam.RegisterOptionControls) ~= "function" then
        return
    end

    local panelData = {
        type = "panel",
        name = MAJOR,
        displayName = MAJOR,
        author = "pc243, Codex",
        version = ADDON_VERSION,
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsData = {
        {
            type = "description",
            text = "Bridge for LibCustomMenu context actions in gamepad mode.",
        },
        {
            type = "checkbox",
            name = "Enable bridge",
            getFunc = function()
                return self.enabled
            end,
            setFunc = function(value)
                self:SetEnabled(value)
            end,
            default = DEFAULTS.enabled,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Debug mode",
            getFunc = function()
                return self.debug
            end,
            setFunc = function(value)
                self:SetDebugEnabled(value)
            end,
            default = DEFAULTS.debug,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Verbose debug",
            getFunc = function()
                return self.debugVerbose
            end,
            setFunc = function(value)
                self:SetDebugVerbose(value)
            end,
            default = DEFAULTS.debugVerbose,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Show TTC price in gamepad tooltip",
            getFunc = function()
                return self:_shouldShowTtcTooltipPrice()
            end,
            setFunc = function(value)
                self:SetShowTtcPriceInTooltip(value)
            end,
            default = DEFAULTS.showTtcPriceInTooltip,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Show expanded TTC details",
            getFunc = function()
                return self:_shouldShowTtcTooltipDetails()
            end,
            setFunc = function(value)
                self:SetShowTtcPriceDetailsInTooltip(value)
            end,
            disabled = function()
                return not self:_shouldShowTtcTooltipPrice()
            end,
            default = DEFAULTS.showTtcPriceDetailsInTooltip,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Show junk status in gamepad tooltip",
            getFunc = function()
                return self:_shouldShowJunkStatusInTooltip()
            end,
            setFunc = function(value)
                self:SetShowJunkStatusInTooltip(value)
            end,
            default = DEFAULTS.showJunkStatusInTooltip,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Show vendor price in gamepad tooltip",
            getFunc = function()
                return self:_shouldShowVendorPriceInTooltip()
            end,
            setFunc = function(value)
                self:SetShowVendorPriceInTooltip(value)
            end,
            default = DEFAULTS.showVendorPriceInTooltip,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Show bound status in gamepad tooltip",
            getFunc = function()
                return self:_shouldShowBoundStatusInTooltip()
            end,
            setFunc = function(value)
                self:SetShowBoundStatusInTooltip(value)
            end,
            default = DEFAULTS.showBoundStatusInTooltip,
            width = "full",
        },
        {
            type = "button",
            name = "Print debug log to chat",
            func = function()
                self:DumpDebugLog(60)
            end,
            width = "half",
        },
        {
            type = "button",
            name = "Clear debug log",
            func = function()
                self:ClearDebugLog()
            end,
            width = "half",
        },
    }

    lam:RegisterAddonPanel(MAJOR .. "_Settings", panelData)
    lam:RegisterOptionControls(MAJOR .. "_Settings", optionsData)
    self._settingsPanelRegistered = true
    LogTrace("Settings panel registered in LibAddonMenu")
end

function bridge:_captureMenuEntry(capture, labelValue, callback, itemType, enabled)
    local itemTypeValue = itemType or MENU_ADD_OPTION_LABEL
    if itemTypeValue == MENU_ADD_OPTION_HEADER then
        return #capture.entries
    end

    enabled = EvaluateValue(enabled, ZO_Menu, capture.contextControl)
    if enabled == false then
        return #capture.entries
    end

    local label = ResolveLabel(labelValue, capture.contextControl)
    if not label or IsDividerLabel(label) then
        return #capture.entries
    end

    if itemTypeValue == MENU_ADD_OPTION_CHECKBOX then
        label = "[ ] " .. label
    end

    if type(callback) ~= "function" then
        return #capture.entries
    end

    capture.entries[#capture.entries + 1] = {
        kind = "action",
        label = label,
        callback = function()
            SafeCallCallbackWithContext(callback, capture.contextControl)
        end,
    }
    LogTrace(string.format("Captured action: %s", tostring(label)))

    return #capture.entries
end

function bridge:_captureSubMenuEntries(capture, submenuLabelValue, entries, submenuCallback)
    local submenuLabel = ResolveLabel(submenuLabelValue, capture.contextControl)
    if not submenuLabel then
        LogTrace("Skipped submenu with empty label")
        return #capture.entries
    end

    local submenuEntries = entries
    if type(submenuEntries) == "function" then
        submenuEntries = EvaluateValue(submenuEntries, ZO_Menu, capture.contextControl)
    end

    if type(submenuEntries) ~= "table" then
        LogTrace(string.format("Skipped submenu '%s': entries is %s", tostring(submenuLabel), type(submenuEntries)))
        return #capture.entries
    end

    local submenuActionEntries = {}

    for i = 1, #submenuEntries do
        local entry = submenuEntries[i]
        if type(entry) == "table" then
            local visible = EvaluateValue(entry.visible, ZO_Menu, capture.contextControl)
            if visible ~= false then
                local disabled = EvaluateValue(entry.disabled or false, ZO_Menu, capture.contextControl)
                if not disabled then
                    local itemTypeValue = entry.itemType or MENU_ADD_OPTION_LABEL
                    if itemTypeValue ~= MENU_ADD_OPTION_HEADER then
                        local childLabel = ResolveLabel(entry.label or entry.name or entry[1], capture.contextControl)
                        if childLabel and not IsDividerLabel(childLabel) then
                            if itemTypeValue == MENU_ADD_OPTION_CHECKBOX then
                                local checked = EvaluateValue(entry.checked or false, ZO_Menu, capture.contextControl)
                                childLabel = string.format("[%s] %s", checked and "x" or " ", childLabel)
                            end

                            local callback = entry.callback or entry.func or entry[2]
                            if type(callback) == "function" then
                                submenuActionEntries[#submenuActionEntries + 1] = {
                                    label = childLabel,
                                    callback = function()
                                        SafeCallCallbackWithContext(callback, capture.contextControl)
                                    end,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if #submenuActionEntries == 0 then
        LogTrace(string.format("Skipped submenu '%s': no visible actions", submenuLabel))
        return #capture.entries
    end

    capture.entries[#capture.entries + 1] = {
        kind = "submenu",
        label = submenuLabel,
        entries = submenuActionEntries,
        callback = type(submenuCallback) == "function" and function()
            SafeCallCallbackWithContext(submenuCallback, capture.contextControl)
        end or nil,
    }
    LogTrace(string.format("Captured submenu: %s (%d items)", submenuLabel, #submenuActionEntries))

    return #capture.entries
end

function bridge:_beginCapture(lcm)
    local capture = {
        entries = {},
        originals = {},
        contextControl = nil,
    }

    capture.originals.AddMenuItem = AddMenuItem
    capture.originals.AddCustomMenuItem = AddCustomMenuItem
    capture.originals.AddCustomSubMenuItem = AddCustomSubMenuItem
    capture.originals.AddCustomMenuTooltip = AddCustomMenuTooltip
    capture.originals.ShowMenu = ShowMenu
    capture.originals.ClearMenu = ClearMenu

    _G.AddMenuItem = function(mytext, myfunction, itemType, myFont, normalColor, highlightColor, itemYPad, horizontalAlignment, isHighlighted, onEnter, onExit, enabled)
        return bridge:_captureMenuEntry(capture, mytext, myfunction, itemType, enabled)
    end

    _G.AddCustomMenuItem = function(mytext, myfunction, itemType, myFont, normalColor, highlightColor, itemYPad, horizontalAlignment, isHighlighted, onEnter, onExit, enabled)
        return bridge:_captureMenuEntry(capture, mytext, myfunction, itemType, enabled)
    end

    _G.AddCustomSubMenuItem = function(mytext, entries, myfont, normalColor, highlightColor, itemYPad, callback)
        return bridge:_captureSubMenuEntries(capture, mytext, entries, callback)
    end

    _G.AddCustomMenuTooltip = function()
        return nil
    end

    _G.ShowMenu = function()
        return nil
    end

    _G.ClearMenu = function()
        return nil
    end

    if type(lcm) == "table" and type(lcm.AddMenuItem) == "function" then
        capture.originals.LibAddMenuItem = lcm.AddMenuItem
        lcm.AddMenuItem = function(...)
            return _G.AddMenuItem(...)
        end
    end

    return capture
end

function bridge:_endCapture(lcm, capture)
    if not capture or not capture.originals then
        return
    end

    _G.AddMenuItem = capture.originals.AddMenuItem
    _G.AddCustomMenuItem = capture.originals.AddCustomMenuItem
    _G.AddCustomSubMenuItem = capture.originals.AddCustomSubMenuItem
    _G.AddCustomMenuTooltip = capture.originals.AddCustomMenuTooltip
    _G.ShowMenu = capture.originals.ShowMenu
    _G.ClearMenu = capture.originals.ClearMenu

    if type(lcm) == "table" and capture.originals.LibAddMenuItem then
        lcm.AddMenuItem = capture.originals.LibAddMenuItem
    end
end

function bridge:_runContextCallbacks(lcm, inventorySlot, slotActions)
    if self._isCapturing then
        return {}
    end

    self._isCapturing = true
    local capture = self:_beginCapture(lcm)
    capture.contextControl = inventorySlot
    LogTrace("Context capture started")
    local originalGetSlotType = ZO_InventorySlot_GetType

    local originalContextMenuMode = slotActions and slotActions.m_contextMenuMode

    local ok, err = pcall(function()
        local early = tonumber(lcm.CATEGORY_EARLY)
        local late = tonumber(lcm.CATEGORY_LATE)
        if early == nil or late == nil then
            return
        end
        local contextMenuRegistry = lcm.contextMenuRegistry
        local hasFireCallbacks = type(contextMenuRegistry) == "table" and type(contextMenuRegistry.FireCallbacks) == "function"
        local summary, totalCallbacks = self:_summarizeContextRegistry()
        LogTrace(string.format("Context registry callbacks: total=%d (%s)", tonumber(totalCallbacks or 0), tostring(summary)))
        if type(ZO_InventorySlot_GetType) == "function" then
            local slotType = ZO_InventorySlot_GetType(inventorySlot)
            LogTrace(string.format("Slot type: %s", tostring(slotType)))
        end

        if type(originalGetSlotType) == "function" then
            ZO_InventorySlot_GetType = function(slot)
                local resolved = originalGetSlotType(slot)
                if slot ~= inventorySlot then
                    return resolved
                end

                local normalized = bridge:_resolveNormalizedSlotType(slot, resolved)
                if normalized ~= resolved then
                    LogTrace(string.format("Normalized slot type %s -> %s", tostring(resolved), tostring(normalized)))
                    return normalized
                end
                return resolved
            end
        end

        if slotActions then
            slotActions.m_contextMenuMode = true
        end

        if hasFireCallbacks then
            LogTrace("Running callbacks via LibCustomMenu contextMenuRegistry:FireCallbacks")
            for category = early, late do
                local callbackOk, callbackErr = pcall(contextMenuRegistry.FireCallbacks, contextMenuRegistry, category, inventorySlot, slotActions)
                if not callbackOk then
                    LogDebug(callbackErr)
                end
            end
        else
            LogTrace("Running callbacks via internal callback cache (fallback mode)")
            for category = early, late do
                local callbacks = self._contextCallbacks[category]
                if callbacks then
                    for i = 1, #callbacks do
                        local callbackData = callbacks[i]
                        if type(callbackData) == "table" and type(callbackData.func) == "function" then
                            local args = callbackData.args
                            local callbackOk, callbackErr

                            if args and #args > 0 then
                                local callArgs = {}
                                for argIndex = 1, #args do
                                    callArgs[#callArgs + 1] = args[argIndex]
                                end
                                callArgs[#callArgs + 1] = inventorySlot
                                callArgs[#callArgs + 1] = slotActions
                                callbackOk, callbackErr = pcall(callbackData.func, unpackArgs(callArgs))
                            else
                                callbackOk, callbackErr = pcall(callbackData.func, inventorySlot, slotActions)
                            end

                            if not callbackOk then
                                LogDebug(callbackErr)
                            end
                        end
                    end
                end
            end
        end

        if #capture.entries == 0 and totalCallbacks and totalCallbacks > 0 then
            local invoked = self:_invokeRawRegistryHandlers(lcm, inventorySlot, slotActions)
            LogTrace(string.format("Raw registry fallback invoked %d handlers", invoked))
        end
    end)

    if slotActions then
        slotActions.m_contextMenuMode = originalContextMenuMode
    end
    if type(originalGetSlotType) == "function" then
        ZO_InventorySlot_GetType = originalGetSlotType
    end

    self:_endCapture(lcm, capture)
    self._isCapturing = false

    if not ok then
        LogDebug(err)
    end

    LogTrace(string.format("Context capture finished with %d entries", #capture.entries))
    return capture.entries
end

function bridge:_ensureSubmenuDialog()
    if self._submenuDialogRegistered then
        return true
    end

    if type(ZO_Dialogs_RegisterCustomDialog) ~= "function" then
        return false
    end

    if type(GAMEPAD_DIALOGS) ~= "table" or GAMEPAD_DIALOGS.PARAMETRIC == nil then
        return false
    end

    local dialogName = self._submenuDialogName or (MAJOR .. "_SubmenuDialog")
    self._submenuDialogName = dialogName

    ZO_Dialogs_RegisterCustomDialog(dialogName, {
        canQueue = true,
        blockDirectionalInput = true,
        gamepadInfo = {
            dialogType = GAMEPAD_DIALOGS.PARAMETRIC,
            allowRightStickPassThrough = true,
        },
        title = {
            text = function(dialog)
                local data = dialog and dialog.data
                local title = data and data.title
                if type(title) == "string" and title ~= "" then
                    return title
                end
                return SafeGetString(SI_GAMEPAD_SELECT_OPTION, "Select")
            end,
        },
        mainText = {
            text = function(dialog)
                local data = dialog and dialog.data
                local mainText = data and data.mainText
                if type(mainText) == "string" then
                    return mainText
                end
                return ""
            end,
        },
        parametricList = {},
        setup = function(dialog, data)
            local parametricList = dialog.info and dialog.info.parametricList
            if type(parametricList) ~= "table" then
                return
            end

            if type(ZO_ClearNumericallyIndexedTable) == "function" then
                ZO_ClearNumericallyIndexedTable(parametricList)
            else
                while #parametricList > 0 do
                    table.remove(parametricList)
                end
            end

            local submenuEntries = data and data.entries
            if type(submenuEntries) ~= "table" then
                submenuEntries = {}
            end

            for i = 1, #submenuEntries do
                local submenuEntry = submenuEntries[i]
                if type(submenuEntry) == "table" then
                    local submenuLabel = submenuEntry.label or submenuEntry.name or submenuEntry[1]
                    if type(submenuLabel) ~= "string" then
                        submenuLabel = tostring(submenuLabel or "")
                    end
                    local submenuCallback = submenuEntry.callback or submenuEntry.func or submenuEntry[2]
                    if submenuLabel ~= "" then
                    local entryData
                    if type(ZO_GamepadEntryData) == "table" and type(ZO_GamepadEntryData.New) == "function" then
                        entryData = ZO_GamepadEntryData:New(submenuLabel)
                        if type(entryData.SetIconTintOnSelection) == "function" then
                            entryData:SetIconTintOnSelection(true)
                        end
                    else
                        entryData = { text = submenuLabel }
                    end

                    if type(ZO_SharedGamepadEntry_OnSetup) == "function" then
                        entryData.setup = ZO_SharedGamepadEntry_OnSetup
                    end

                    entryData._lgcmbCallback = type(submenuCallback) == "function" and submenuCallback or nil
                    table.insert(parametricList, {
                        template = "ZO_GamepadItemEntryTemplate",
                        entryData = entryData,
                    })
                    end
                end
            end

            if type(dialog.setupFunc) == "function" then
                dialog:setupFunc()
            end

            if dialog.entryList and type(dialog.entryList.SetSelectedIndexWithoutAnimation) == "function" then
                pcall(dialog.entryList.SetSelectedIndexWithoutAnimation, dialog.entryList, 1, true, false)
            end
        end,
        buttons = {
            {
                keybind = "DIALOG_NEGATIVE",
                text = SafeGetString(SI_DIALOG_CANCEL, "Cancel"),
            },
            {
                keybind = "DIALOG_PRIMARY",
                text = SafeGetString(SI_GAMEPAD_SELECT_OPTION, "Select"),
                callback = function(dialog)
                    local selected = dialog and dialog.entryList and SafeGetTargetData(dialog.entryList)
                    local callback = selected and (selected._lgcmbCallback or (selected.entryData and selected.entryData._lgcmbCallback))
                    ZO_Dialogs_ReleaseDialogOnButtonPress(dialogName)
                    if type(callback) == "function" then
                        SafeCallCallback(callback)
                    end
                end,
            },
        },
    })

    self._submenuDialogRegistered = true
    return true
end

function bridge:_showSubmenuDialog(submenuLabel, submenuEntries, submenuCallback)
    if type(submenuCallback) == "function" then
        SafeCallCallback(submenuCallback)
    end

    if type(submenuEntries) ~= "table" or #submenuEntries == 0 then
        return
    end

    if not self:_ensureSubmenuDialog() then
        return
    end

    ZO_Dialogs_ShowDialog(self._submenuDialogName, {
        title = submenuLabel,
        entries = submenuEntries,
    })
end

function bridge:_appendEntriesToSlotActions(slotActions, entries, inventorySlot)
    if type(slotActions) ~= "table" or type(slotActions.AddSlotAction) ~= "function" then
        return
    end

    local knownNames = CollectExistingActionNames(slotActions)
    local hasSubmenuDialog = false
    local addedCount = 0

    local function AddUniqueAction(label, callback)
        if type(label) ~= "string" or label == "" then
            return
        end
        if type(callback) ~= "function" then
            return
        end
        if knownNames[label] then
            return
        end

        knownNames[label] = true
        local actionName = bridge:_ensureActionStringId(label)
        -- Keep this nil for compatibility with gamepad action dialogs that derive labels from raw action metadata.
        slotActions:AddSlotAction(actionName, callback, nil)
        StampActionLabel(slotActions, label, callback)
        addedCount = addedCount + 1
    end

    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" then
            if entry.kind == "submenu" then
                local submenuEntries = entry.entries
                if type(submenuEntries) == "table" and #submenuEntries > 0 then
                    if hasSubmenuDialog then
                        AddUniqueAction(entry.label, function()
                            bridge:_showSubmenuDialog(entry.label, submenuEntries, entry.callback)
                        end)
                    else
                        for subIndex = 1, #submenuEntries do
                            local submenuEntry = submenuEntries[subIndex]
                            if
                                type(submenuEntry) == "table"
                                and type(submenuEntry.label) == "string"
                                and submenuEntry.label ~= ""
                                and type(submenuEntry.callback) == "function"
                            then
                                AddUniqueAction(string.format("%s: %s", entry.label, submenuEntry.label), submenuEntry.callback)
                            end
                        end
                    end
                end
            else
                AddUniqueAction(entry.label, entry.callback)
            end
        end
    end

    local nativeJunkAction = self:_buildNativeJunkAction(inventorySlot)
    if nativeJunkAction then
        AddUniqueAction(nativeJunkAction.label, nativeJunkAction.callback)
    end

    LogTrace(string.format("Injected %d actions from %d captured entries", addedCount, #entries))
end

function bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
    if not self.enabled then
        LogTrace("Skip inject: bridge disabled")
        return
    end

    if type(slotActions) ~= "table" then
        LogTrace("Skip inject: slotActions is invalid")
        return
    end

    if slotActions.m_contextMenuMode then
        LogTrace("Skip inject: already in context menu mode")
        return
    end

    if type(IsInGamepadPreferredMode) == "function" and not IsInGamepadPreferredMode() then
        LogTrace("Skip inject: not in gamepad preferred mode")
        return
    end

    do
        local bagId, slotIndex = self:_resolveBagAndSlot(inventorySlot)
        if bagId == nil or slotIndex == nil then
            LogTrace("Skip inject: slot has no bag/slot index")
            return
        end
    end

    local lcm = LibCustomMenu
    local capturedEntries = {}
    if type(lcm) == "table" then
        capturedEntries = self:_runContextCallbacks(lcm, inventorySlot, slotActions) or {}
    else
        LogTrace("LibCustomMenu missing; injecting native fallback actions only")
    end

    if #capturedEntries == 0 then
        LogTrace("No LibCustomMenu entries captured for this slot")
    end

    self:_appendEntriesToSlotActions(slotActions, capturedEntries, inventorySlot)
end

function bridge:_hookDiscoverSlotActions()
    if self._discoverHooked then
        return
    end

    if type(SecurePostHook) == "function" then
        SecurePostHook("ZO_InventorySlot_DiscoverSlotActionsFromActionList", function(inventorySlot, slotActions)
            bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
        end)
    elseif type(ZO_PostHook) == "function" then
        ZO_PostHook("ZO_InventorySlot_DiscoverSlotActionsFromActionList", function(inventorySlot, slotActions)
            bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
        end)
    else
        return
    end

    self._discoverHooked = true
end

function bridge:_hookRefreshKeybindStrip()
    if self._refreshHooked then
        return
    end

    if type(ZO_ItemSlotActionsController) ~= "table" then
        return
    end

    local hookInstalled = false

    local function OnRefreshKeybindStrip(controller)
        if not controller or type(controller) ~= "table" then
            return
        end

        local slotActions = controller.slotActions
        local inventorySlot = controller.inventorySlot

        if not inventorySlot and type(GAMEPAD_INVENTORY) == "table" and GAMEPAD_INVENTORY.itemActions then
            inventorySlot = GAMEPAD_INVENTORY.itemActions.inventorySlot
        end

        if inventorySlot and slotActions then
            bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
        end
    end

    if type(SecurePostHook) == "function" then
        SecurePostHook(ZO_ItemSlotActionsController, "RefreshKeybindStrip", OnRefreshKeybindStrip)
        hookInstalled = true
    elseif type(ZO_PostHook) == "function" then
        ZO_PostHook(ZO_ItemSlotActionsController, "RefreshKeybindStrip", OnRefreshKeybindStrip)
        hookInstalled = true
    end

    if not hookInstalled then
        return
    end

    self._refreshHooked = true
end

function bridge:Initialize()
    if self._initialized then
        return
    end

    self:_initializeSavedVars()
    self:_initializeSlashCommands()
    self:_initializeSettingsPanel()

    local lcm = LibCustomMenu
    if type(lcm) ~= "table" then
        LogDebug("LibCustomMenu not found; bridge is idle")
        return
    end

    self:_wrapRegisterContextMenu(lcm)
    self:_importExistingCallbacks(lcm)
    self:_hookDiscoverSlotActions()
    self:_hookRefreshKeybindStrip()
    self:_hookTooltipPrice()
    self:_scheduleTooltipPriceHookRetry()
    self:_registerPlayerActivatedHook()

    self._initialized = true
    LogDebug("Initialized")
end

local EVENT_NAMESPACE = MAJOR .. "_OnLoaded"
local PLAYER_ACTIVATED_EVENT_NAMESPACE = MAJOR .. "_PlayerActivated"

function bridge:_registerPlayerActivatedHook()
    if self._playerActivatedHookRegistered then
        return
    end

    if type(EVENT_MANAGER) ~= "table" or type(EVENT_MANAGER.RegisterForEvent) ~= "function" then
        return
    end

    EVENT_MANAGER:RegisterForEvent(PLAYER_ACTIVATED_EVENT_NAMESPACE, EVENT_PLAYER_ACTIVATED, function()
        local hooked = bridge:_hookTooltipPrice()
        if not hooked then
            bridge:_scheduleTooltipPriceHookRetry()
            return
        end

        if type(EVENT_MANAGER.UnregisterForEvent) == "function" then
            EVENT_MANAGER:UnregisterForEvent(PLAYER_ACTIVATED_EVENT_NAMESPACE, EVENT_PLAYER_ACTIVATED)
        end
    end)

    self._playerActivatedHookRegistered = true
end

local function OnAddonLoaded(_, addonName)
    if addonName ~= MAJOR then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED)
    bridge:Initialize()
end

EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED, OnAddonLoaded)

local MAJOR = "LibGamepadContextMenuBridge"
local MINOR = 1

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
bridge._contextCallbacks = bridge._contextCallbacks or {}
bridge._callbackKeys = bridge._callbackKeys or {}
bridge._submenuDialogRegistered = bridge._submenuDialogRegistered or false
bridge._submenuDialogName = bridge._submenuDialogName or (MAJOR .. "_SubmenuDialog")

local unpackArgs = unpack or table.unpack

local function LogDebug(message)
    if bridge.debug and type(d) == "function" then
        d(string.format("[%s] %s", MAJOR, tostring(message)))
    end
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
    local early = lcm and lcm.CATEGORY_EARLY or 1
    local late = lcm and lcm.CATEGORY_LATE or 6

    category = tonumber(category) or late

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

local function ResolveLabel(value)
    value = EvaluateValue(value, ZO_Menu, nil)

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

    self:_rememberContextCallback(func, ResolveCategory(lcm, category), { ... })
end

function bridge:SetEnabled(enabled)
    self.enabled = not not enabled
end

function bridge:_captureMenuEntry(capture, labelValue, callback, itemType, enabled)
    local itemTypeValue = itemType or MENU_ADD_OPTION_LABEL
    if itemTypeValue == MENU_ADD_OPTION_HEADER then
        return #capture.entries
    end

    enabled = EvaluateValue(enabled, ZO_Menu, nil)
    if enabled == false then
        return #capture.entries
    end

    local label = ResolveLabel(labelValue)
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
            SafeCallCallback(callback)
        end,
    }

    return #capture.entries
end

function bridge:_captureSubMenuEntries(capture, submenuLabelValue, entries, submenuCallback)
    local submenuLabel = ResolveLabel(submenuLabelValue)
    if not submenuLabel then
        return #capture.entries
    end

    local submenuEntries = entries
    if type(submenuEntries) == "function" then
        submenuEntries = EvaluateValue(submenuEntries, ZO_Menu, nil)
    end

    if type(submenuEntries) ~= "table" then
        return #capture.entries
    end

    local submenuActionEntries = {}

    for i = 1, #submenuEntries do
        local entry = submenuEntries[i]
        if type(entry) == "table" then
            local visible = EvaluateValue(entry.visible, ZO_Menu, nil)
            if visible ~= false then
                local disabled = EvaluateValue(entry.disabled or false, ZO_Menu, nil)
                if not disabled then
                    local itemTypeValue = entry.itemType or MENU_ADD_OPTION_LABEL
                    if itemTypeValue ~= MENU_ADD_OPTION_HEADER then
                        local childLabel = ResolveLabel(entry.label)
                        if childLabel and not IsDividerLabel(childLabel) then
                            if itemTypeValue == MENU_ADD_OPTION_CHECKBOX then
                                local checked = EvaluateValue(entry.checked or false, ZO_Menu, nil)
                                childLabel = string.format("[%s] %s", checked and "x" or " ", childLabel)
                            end

                            local callback = entry.callback
                            if type(callback) == "function" then
                                submenuActionEntries[#submenuActionEntries + 1] = {
                                    label = childLabel,
                                    callback = function()
                                        SafeCallCallback(callback)
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
        return #capture.entries
    end

    capture.entries[#capture.entries + 1] = {
        kind = "submenu",
        label = submenuLabel,
        entries = submenuActionEntries,
        callback = type(submenuCallback) == "function" and function()
            SafeCallCallback(submenuCallback)
        end or nil,
    }

    return #capture.entries
end

function bridge:_beginCapture(lcm)
    local capture = {
        entries = {},
        originals = {},
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

    local originalContextMenuMode = slotActions and slotActions.m_contextMenuMode

    local ok, err = pcall(function()
        local early = lcm.CATEGORY_EARLY or 1
        local late = lcm.CATEGORY_LATE or 6

        if slotActions then
            slotActions.m_contextMenuMode = true
        end

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
    end)

    if slotActions then
        slotActions.m_contextMenuMode = originalContextMenuMode
    end

    self:_endCapture(lcm, capture)
    self._isCapturing = false

    if not ok then
        LogDebug(err)
    end

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
                if
                    type(submenuEntry) == "table"
                    and type(submenuEntry.label) == "string"
                    and submenuEntry.label ~= ""
                    and type(submenuEntry.callback) == "function"
                then
                    local entryData
                    if type(ZO_GamepadEntryData) == "table" and type(ZO_GamepadEntryData.New) == "function" then
                        entryData = ZO_GamepadEntryData:New(submenuEntry.label)
                        if type(entryData.SetIconTintOnSelection) == "function" then
                            entryData:SetIconTintOnSelection(true)
                        end
                    else
                        entryData = { text = submenuEntry.label }
                    end

                    if type(ZO_SharedGamepadEntry_OnSetup) == "function" then
                        entryData.setup = ZO_SharedGamepadEntry_OnSetup
                    end

                    entryData._lgcmbCallback = submenuEntry.callback
                    table.insert(parametricList, {
                        template = "ZO_GamepadItemEntryTemplate",
                        entryData = entryData,
                    })
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
                    local callback = selected and selected._lgcmbCallback
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

function bridge:_appendEntriesToSlotActions(slotActions, entries)
    if type(slotActions) ~= "table" or type(slotActions.AddSlotAction) ~= "function" then
        return
    end

    local knownNames = CollectExistingActionNames(slotActions)
    local hasSubmenuDialog = self:_ensureSubmenuDialog()

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
        slotActions:AddSlotAction(label, callback, "secondary")
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
end

function bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
    if not self.enabled then
        return
    end

    if type(slotActions) ~= "table" then
        return
    end

    if slotActions.m_contextMenuMode then
        return
    end

    if type(IsInGamepadPreferredMode) == "function" and not IsInGamepadPreferredMode() then
        return
    end

    if type(ZO_Inventory_GetBagAndIndex) == "function" then
        local bagId, slotIndex = ZO_Inventory_GetBagAndIndex(inventorySlot)
        if bagId == nil or slotIndex == nil then
            return
        end
    end

    local lcm = LibCustomMenu
    if type(lcm) ~= "table" then
        return
    end

    local capturedEntries = self:_runContextCallbacks(lcm, inventorySlot, slotActions)
    if not capturedEntries or #capturedEntries == 0 then
        return
    end

    self:_appendEntriesToSlotActions(slotActions, capturedEntries)
end

function bridge:_hookDiscoverSlotActions()
    if self._discoverHooked then
        return
    end

    if type(ZO_PostHook) ~= "function" then
        return
    end

    ZO_PostHook("ZO_InventorySlot_DiscoverSlotActionsFromActionList", function(inventorySlot, slotActions)
        bridge:_tryInjectGamepadContextActions(inventorySlot, slotActions)
    end)

    self._discoverHooked = true
end

function bridge:Initialize()
    if self._initialized then
        return
    end

    local lcm = LibCustomMenu
    if type(lcm) ~= "table" then
        LogDebug("LibCustomMenu not found; bridge is idle")
        return
    end

    self:_wrapRegisterContextMenu(lcm)
    self:_importExistingCallbacks(lcm)
    self:_hookDiscoverSlotActions()

    self._initialized = true
    LogDebug("Initialized")
end

local EVENT_NAMESPACE = MAJOR .. "_OnLoaded"

local function OnAddonLoaded(_, addonName)
    if addonName ~= MAJOR then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED)
    bridge:Initialize()
end

EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_ADD_ON_LOADED, OnAddonLoaded)

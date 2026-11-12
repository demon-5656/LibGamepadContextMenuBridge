-- Contract regressions. Native integration uses the pinned ESO source directory.
local mode = arg[2]
arg[2] = "helpers"
local h = dofile("scripts/tests/regression.lua")
arg[2] = mode
local fresh, check, contains = h.fresh, h.check, h.contains
local selected = arg[2]
local groups = 0
local function test(name, fn)
    if not selected or selected == name then
        fn()
        groups = groups + 1
        print("PASS contract " .. name)
    end
end
local function itemFixture()
    local b = fresh()
    local state = {id="A",junk=false,locked=false,eligible=true,gamepad=true,calls=0}
    local slot = {bagId=BAG_BACKPACK,slotIndex=7}
    GetItemUniqueId = function(bag,index) check(bag==1 and index==7,"wrong identity address");return state.id end
    Id64ToString = function(id) return id end
    IsInGamepadPreferredMode = function() return state.gamepad end
    IsItemJunk = function() return state.junk end
    IsItemPlayerLocked = function() return state.locked end
    CanItemBeMarkedAsJunk = function() return state.eligible end
    SetItemIsJunk = function(_,_,value) state.calls=state.calls+1;state.junk=value end
    ZO_CreateStringId("SI_ITEM_ACTION_MARK_AS_JUNK","Mark junk")
    ZO_CreateStringId("SI_ITEM_ACTION_UNMARK_AS_JUNK","Unmark junk")
    return b,state,slot
end
local function actions()
    local a = {m_slotActions={}}
    function a:AddSlotAction(id, callback, kind, visible, options)
        self.m_slotActions[#self.m_slotActions+1]={GetString(id),callback,kind,visible,options}
    end
    return a
end

test("identity",function()
    local b,s,slot = itemFixture()
    local a = b:_buildNativeJunkAction(slot)
    s.id="B" -- The link can be identical; the physical instance cannot.
    a.callback()
    check(s.calls==0,"stale junk action affected replacement instance")
    for _,field in ipairs({"locked","eligible","junk","gamepad","enabled"}) do
        b,s,slot=itemFixture()
        a=b:_buildNativeJunkAction(slot)
        if field=="enabled" then b.enabled=false
        elseif field=="eligible" or field=="gamepad" then s[field]=false else s[field]=true end
        a.callback()
        check(s.calls==0,"junk eligibility not rechecked: "..field)
    end
    b,s,slot=itemFixture(); a=b:_buildNativeJunkAction(slot);a.callback()
    check(s.calls==1 and s.junk,"valid junk action lost")
    b,s,slot=itemFixture();s.id="0"
    check(b:_buildNativeJunkAction(slot)==nil,"empty slot given an action")
    for _,reason in ipairs({"replacement","disabled","mode","empty"}) do
        b,s,slot=itemFixture()
        b._buildNativeJunkAction=function() end
        local out=actions()
        b:_appendEntriesToSlotActions(out,{{label="Third party",callback=function() s.calls=s.calls+1 end}},slot)
        if reason=="replacement" then s.id="B" elseif reason=="disabled" then b.enabled=false
        elseif reason=="mode" then s.gamepad=false else s.id="0" end
        out.m_slotActions[1][2]()
        check(s.calls==0,"injected callback ignored current identity/mode: "..reason)
    end
end)

test("menu-contracts",function()
    local b=fresh()
    check(MENU_ADD_OPTION_CHECKBOX==2 and MENU_ADD_OPTION_HEADER==100,"fixtures use wrong native constants")
    local c={entries={},contextControl={}}
    b:_captureMenuEntry(c,"Mouse checkbox",function() error("control-dependent checkbox executed") end,2)
    check(#c.entries==0,"top-level control-dependent checkbox advertised")
    local calls=0
    b:_captureSubMenuEntries(c,"Parent",function() calls=calls+1;error("fake parent row supplied") end,function() calls=calls+1 end)
    check(calls==0 and #c.entries==0,"control-dependent submenu builder executed")
    b:_captureSubMenuEntries(c,"Parent",{{label="Child",callback=function() end}},function() calls=calls+1 end)
    check(#c.entries==1 and c.entries[1].callback==nil and #c.entries[1].entries==1,"parent click must not masquerade as no-arg action")
    check(calls==0,"parent invoked at capture")
    for _,value in ipairs({"absent","false","nil","true","truthy"}) do
        c={entries={},contextControl={}}
        local seen=0
        local e={label="Child",callback=function() end}
        if value~="absent" then e.visible=function(...)
            seen=seen+1;check(select("#",...)==1 and (...)==ZO_Menu,"visible must get only ZO_Menu")
            if value=="false" then return false elseif value=="true" then return true elseif value=="truthy" then return 1 end
        end end
        b:_captureSubMenuEntries(c,"Parent",{e})
        local expected=value=="absent" or value=="true" or value=="truthy"
        check((#c.entries>0)==expected,"wrong visible truthiness: "..value)
        check(seen==(value=="absent" and 0 or 1),"visible evaluated repeatedly")
    end
    for _,field in ipairs({"label","checked","disabled"}) do
        c={entries={},contextControl={}}
        local e={label="Child",itemType=2,callback=function() end}
        e[field]=function() error("invented item control for "..field) end
        b:_captureSubMenuEntries(c,"Parent",{e})
        check(#c.entries==0,"control-dependent evaluator exposed: "..field)
    end
    c={entries={},contextControl={}}
    local states={}
    b:_captureSubMenuEntries(c,"Parent",{
        {label="Off",itemType=2,checked=false,callback=function(v) states[1]=v end},
        {label="On",itemType=2,checked=true,callback=function(v) states[2]=v end},
    })
    c.entries[1].entries[1].callback();c.entries[1].entries[2].callback()
    check(states[1]==true and states[2]==false,"boolean-only submenu checkboxes lost")
end)

local native = os.getenv("ESO_NATIVE_SOURCE")
local function loadNative()
    assert(native,"set ESO_NATIVE_SOURCE to the pinned ESO source directory")
    GetCVar=function() return "0" end
    zo_mixin=function(dest,...) for i=1,select("#",...) do for k,v in pairs(select(i,...)) do dest[k]=v end end end
    dofile(native.."/esoui/libraries/utility/baseobject.lua")
    dofile(native.."/esoui/libraries/utility/zo_callbackobject.lua")
    dofile(native.."/esoui/ingame/inventory/inventoryslotactions.lua")
    dofile(native.."/esoui/ingame/inventory/itemslotactioncontroller.lua")
    ZO_ClearTable=function(t) for k in pairs(t) do t[k]=nil end end
    ZO_ClearNumericallyIndexedTable=ZO_ClearTable
    IsUnitDead=function() return false end
    ZO_InventorySlot_GetType=function() return SLOT_TYPE_ITEM end
end
local function registryFixture(builder)
    local registry=ZO_CallbackObject:New()
    registry:RegisterCallback(1,builder)
    LibCustomMenu.CATEGORY_EARLY,LibCustomMenu.CATEGORY_LATE=1,1
    LibCustomMenu.contextMenuRegistry=registry
    return registry
end

test("capture-transaction",function()
    local b,s,slot=itemFixture();loadNative()
    local a=ZO_InventorySlotActions:New(false)
    ZO_CreateStringId("SI_BASE","Base");ZO_CreateStringId("SI_EXTRA","Extra")
    local baseCallback=function() end
    a:AddSlotAction(SI_BASE,baseCallback,"primary",nil,{visibleWhenDead=true})
    local originalRows,originalKeys=a.m_slotActions,a.m_keybindActions
    local marker=function() end
    AddMenuItem,AddCustomMenuItem,AddCustomSubMenuItem,AddCustomMenuTooltip,ShowMenu,ClearMenu=marker,marker,marker,marker,marker,marker
    local registry=registryFixture(function(_,sa)
        sa:GetSlotAction(1)[1]="Adjusted"
        sa:GetSlotAction(1)[5].changed=true
        sa:AddSlotAction(SI_EXTRA,function() end,"keybind2",nil,{visibleWhenDead=true})
        check(sa:GetNumSlotActions()==2 and sa:GetAction(2,"keybind")[1]=="Extra","native add/read facade incoherent")
        error("builder failed after native writes")
    end)
    local ok,err=pcall(function() b:_runContextCallbacks(LibCustomMenu,slot,a) end)
    check(not ok and tostring(err):find("builder failed after native writes",1,true),"native builder exception swallowed")
    check(a.m_slotActions==originalRows and a.m_keybindActions==originalKeys and #originalRows==1,"native arrays leaked from failed capture")
    check(originalRows[1][1]=="Base" and not originalRows[1][5].changed and a.m_numContextMenuActions==0,"native adjustment leaked from failed capture")
    check(registry:GetFireCallbackDepth()==0 and not b._isCapturing and AddMenuItem==marker,"failed capture cleanup incomplete")
    LibCustomMenu.AddMenuItem=nil
    local c=b:_beginCapture(LibCustomMenu);b:_endCapture(LibCustomMenu,c)
    check(LibCustomMenu.AddMenuItem==nil,"nil original not restored")
    registry.GetFireCallbackDepth=function() error("setup-depth") end
    ok,err=pcall(function() b:_runContextCallbacks(LibCustomMenu,slot,a) end)
    check(not ok and tostring(err):find("setup-depth",1,true),"setup error lost")
    check(not b._isCapturing and AddMenuItem==marker and LibCustomMenu.AddMenuItem==nil,"setup failure left globals installed")
    local hostile=setmetatable({CATEGORY_EARLY=1,CATEGORY_LATE=1,contextMenuRegistry=registry},{__newindex=function() error("setup-write") end})
    ok,err=pcall(function() b:_runContextCallbacks(hostile,slot,a) end)
    check(not ok and not b._isCapturing and AddMenuItem==marker,"partial setup failure was not rolled back")
end)

test("native-state",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    local a=ZO_InventorySlotActions:New(false)
    ZO_CreateStringId("SI_BASE","Base");ZO_CreateStringId("SI_EXTRA","Extra");ZO_CreateStringId("SI_SILENT","Silent")
    a:AddSlotAction(SI_BASE,function() end,"primary",nil,{visibleWhenDead=true})
    registryFixture(function(_,sa)
        sa:GetSlotAction(1)[1]="Adjusted"
        sa:AddSlotAction(SI_EXTRA,function() s.calls=s.calls+1 end,"keybind2",function() return s.eligible end,{visibleWhenDead=true})
        sa:AddSlotAction(SI_SILENT,function() s.calls=s.calls+1 end,nil,nil,{visibleWhenDead=false})
        check(sa:GetNumSlotActions()==3 and sa:GetSlotAction(2)[3]=="keybind2","native read after add broken")
        check(sa:GetSlotAction(3)[5].visibleWhenDead==false,"native options lost")
    end)
    local entries=b:_runContextCallbacks(LibCustomMenu,slot,a)
    check(#a.m_slotActions==1 and a.m_slotActions[1][1]=="Base","capture changed live state before merge")
    b:_appendEntriesToSlotActions(a,entries,slot)
    check(#a.m_slotActions==3 and a.m_slotActions[1][1]=="Adjusted","native actions duplicated or adjustment lost")
    check(a.m_keybindActions[2][3]=="keybind" and a.m_slotActions[2][3]=="keybind2","native type/keybind semantics lost")
    check(a.m_slotActions[2][5].visibleWhenDead and a.m_slotActions[3][5].visibleWhenDead==false,"native options not retained")
    s.eligible=false;a.m_slotActions[2][2]();a.m_keybindActions[2][2]()
    check(s.calls==0,"hidden native action still executable")
    s.eligible=true;a.m_keybindActions[2][2]();check(s.calls==1,"valid keybind action lost")
    s.id="B";a.m_slotActions[3][2]();check(s.calls==1,"native direct callback lacked identity guard")
end)

test("native-rebuild",function()
    for _,empty in ipairs({true,false}) do
        local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
        local runs=0
        registryFixture(function() runs=runs+1;if not empty then AddMenuItem("Action",function() end) end end)
        SecurePostHook=function(target,name,hook)
            if type(target)=="string" then target,name,hook=_G,target,name end
            local original=target[name]
            target[name]=function(...) local result=original(...);hook(...);return result end
        end
        ZO_InventorySlot_DiscoverSlotActionsFromActionList=function() end
        KEYBIND_STRIP={HasKeybindButtonGroup=function() return false end,AddKeybindButtonGroup=function() end,RemoveKeybindButtonGroup=function() end}
        b:_hookDiscoverSlotActions();b:_hookRefreshKeybindStrip()
        local controller=ZO_ItemSlotActionsController:New(nil,nil,false)
        controller:SetInventorySlot(slot)
        check(runs==1,"native rebuild dispatched context registry twice")
        controller:RefreshKeybindStrip();check(runs==1,"refresh-only replayed builder")
        controller:RebuildActions();check(runs==2,"next native rebuild did not dispatch live registry")
    end
end)

test("price-cache",function()
    local b=fresh()
    local now,calls,price=1000,0,10
    GetGameTimeMilliseconds=function() return now end
    b._isBoundItem=function() return false end
    ZO_CurrencyControl_FormatCurrency=function(v) return tostring(v) end
    local link="|H1:item:123:|hItem|h"
    local before=b:_getCachedTtcTooltipLines(link)
    check(#before==0,"missing provider should be empty")
    TamrielTradeCentrePrice={PriceTable={Data={},TimeStamp=1},GetPriceInfo=function() calls=calls+1;return {SuggestedPrice=price} end}
    local lines=b:_buildTooltipInfoLinesByLink(link,3,60,false)
    check(contains(lines,"TTC: 10") and contains(lines,"TTC x3: 30") and calls==1,"provider readiness or request-local snapshot broken")
    TamrielTradeCentrePrice.GetPriceInfo=function() calls=calls+1;price=price+1;return {SuggestedPrice=price} end
    now=now+10000
    calls=0;lines=b:_buildTooltipInfoLinesByLink(link,3,60,false)
    check(calls==1 and contains(lines,"TTC: 11") and contains(lines,"TTC x3: 33"),"unit/stack/comparison did not share a snapshot")
    for _,change in ipairs({"table","data","timestamp","region"}) do
        price=price+10
        if change=="table" then TamrielTradeCentrePrice.PriceTable={Data={},TimeStamp=1}
        elseif change=="data" then TamrielTradeCentrePrice.PriceTable.Data={}
        elseif change=="timestamp" then TamrielTradeCentrePrice.PriceTable.TimeStamp=2
        else GetWorldName=function() return "NA Megaserver" end end
        local old=calls;lines=b:_getCachedTtcTooltipLines(link)
        check(calls==old+1 and contains(lines,"TTC: "..price),"provider fingerprint ignored "..change)
    end
    TamrielTradeCentrePrice.GetPriceInfo=function() calls=calls+1;return nil end
    now=now+10000
    check(#b:_getCachedTtcTooltipLines(link)==0,"negative result not empty")
    TamrielTradeCentrePrice.GetPriceInfo=function() calls=calls+1;return {SuggestedPrice=99} end
    local old=calls;check(#b:_getCachedTtcTooltipLines(link)==0 and calls==old,"negative result not cached")
    now=now+10000;check(contains(b:_getCachedTtcTooltipLines(link),"TTC: 99"),"negative cache never expired")
    local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
    for i=1,520 do b:_getCachedTtcTooltipLines("|H1:item:"..i..":|hItem|h") end
    check(count(b._tooltipTtcCache)==b._tooltipTtcCacheSize and b._tooltipTtcCacheSize<=256,"price-cache eviction counter wrong")
end)

test("recipe-units",function()
    local b=fresh()
    GetGameTimeMilliseconds=function() return 1000 end
    local quantity,calls=4,0
    GetRecipeResultQuantity=function(list,recipe,iterations)
        check(list==2 and recipe==3 and iterations==1,"recipe output must use one operation")
        calls=calls+1;return quantity
    end
    local result="|H1:item:99:|hResult|h"
    local mat="|H1:item:98:|hMat|h"
    b._collectRecipeIngredients=function() return {{itemLink=mat,name="Mat",quantity=5}} end
    b._getItemLinkQualityHex=function() return "FFFFFF" end
    b._getTtcPriceInfo=function(_,link) return {SuggestedPrice=link==result and 20 or 10} end
    b._formatTooltipInfoCurrency=function(_,v) return tostring(v) end
    b._formatCompactTooltipCurrency=function(_,v) return tostring(v) end
    local context={recipeListIndex=2,recipeIndex=3}
    local lines=b:_buildCraftMaterialCostLines(result,context)
    check(calls==1 and contains(lines,"vs crafted: +30") and contains(lines,"per craft") and contains(lines,"output x4"),"recipe mixed per-item value with per-craft cost")
    quantity=1;lines=b:_buildCraftMaterialCostLines(result,context)
    check(contains(lines,"vs crafted: -30") and contains(lines,"output x1"),"single-output recipe changed basis")
    quantity=nil;lines=b:_buildCraftMaterialCostLines(result,context)
    check(not contains(lines,"vs crafted:") and contains(lines,"output unknown"),"unknown output presented a reliable delta")
end)

local function control(width,height)
    local c={hidden=false,width=width or 500,height=height or 600}
    function c:IsControlHidden() return self.hidden end
    function c:IsHidden() return self.hidden end
    function c:GetWidth() return self.width end
    function c:GetHeight() return self.height end
    function c:GetParent() error("styled GetParent must not be used as native ancestry") end
    return c
end
local function overlayFixture()
    local b=fresh()
    local state={now=1000,rendered=0,prepared=0,anchors=0,ready=true,queue={}}
    GetGameTimeMilliseconds=function() return state.now end
    zo_callLater=function(fn) state.queue[#state.queue+1]=fn end
    local w=control()
    w.hidden=true
    function w:SetHidden(v) self.hidden=v end
    function w:SetHandler(event,fn) self[event]=fn end
    local overlay={window=w,label={}}
    b._overlayWindow=overlay
    b._ensureOverlayWindow=function() return overlay end
    b._buildCompactOverlayLines=function(_,lines) state.prepared=state.prepared+1;return lines end
    b._renderOverlayLines=function(_,_,lines) state.rendered=state.rendered+1;state.lines=lines end
    b._resizeOverlayToText=function() end
    b._positionOverlay=function() state.anchors=state.anchors+1;return state.ready end
    return b,state,w
end

test("overlay-owner",function()
    local b=fresh()
    local tip,owner,other=control(300,1800),control(500,600),control()
    tip.GetParent=function() return nil end -- Native styled root contract.
    GAMEPAD_TOOLTIPS={GetTooltip=function() return other end}
    b._overlayTooltipControl=tip;b._overlayOwnerControl=owner
    check(b:_getOverlayAnchorContainer()==owner,"scrolling content used instead of explicit owner container")
    owner.hidden=true
    check(not b:_shouldKeepOverlayVisible() and b:_getActiveOverlayTooltip()==nil,"hidden owner substituted by unrelated tooltip")
end)

test("overlay-retry",function()
    local b,s,w=overlayFixture()
    s.ready=false
    local owner=control()
    b:_showOverlayLines({"Price"},"bag",owner,nil,nil,owner)
    check(w.hidden,"pending new request exposed old anchor")
    while #s.queue>0 do table.remove(s.queue,1)() end
    check(w.hidden and w.OnUpdate==nil,"exhausted retry showed unanchored window")
    check(s.rendered==1 and s.prepared==1 and s.anchors==7,"retry repeated presentation work")
    s.ready=true;b:_showOverlayLines({"Old"},"bag",owner,nil,nil,owner)
    s.ready=false;b:_showOverlayLines({"New"},"bag",owner,nil,nil,owner)
    check(w.hidden,"pending replacement retained old visible window")
    b:_hideOverlay();s.ready=true;local renders=s.rendered
    while #s.queue>0 do table.remove(s.queue,1)() end
    check(w.hidden and s.rendered==renders,"cancelled owner retry resurrected window")
end)

test("overlay-expiry",function()
    local b,s,w=overlayFixture()
    b._isBoundItem=function() return false end
    GetItemLinkValue=function() return 1 end
    ZO_CurrencyControl_FormatCurrency=function(v) return tostring(v) end
    local calls,price=0,10
    TamrielTradeCentrePrice={PriceTable={Data={},TimeStamp=1},GetPriceInfo=function() calls=calls+1;return {SuggestedPrice=price} end}
    local tip,owner=control(300,1600),control()
    local link="|H1:item:123:|hItem|h"
    b:_appendGamepadTooltipInfoByLink(tip,link,2,nil,"guildstore",nil,owner)
    check(calls==1 and not w.hidden,"initial visible price missing")
    price=20;s.now=11000;b:_refreshOverlayVisibility()
    check(calls==2 and contains(s.lines,"TTC: 20") and contains(s.lines,"TTC x2: 40"),"current visible model did not refresh at TTL")
    owner.hidden=true;s.now=21000;b:_refreshOverlayVisibility()
    check(w.hidden and calls==2,"hidden owner polled/rebuilt provider")
    s.now=31000;b:_refreshOverlayVisibility();check(calls==2,"hidden window kept polling")
    owner.hidden=false;b:_appendGamepadTooltipInfoByLink(tip,link,2,nil,"guildstore",nil,owner)
    b.enabled=false;s.now=41000;b:_refreshOverlayVisibility()
    check(w.hidden and calls==3,"disabled visible model refreshed")
end)

test("capture-setup",function()
    local b,s,slot=itemFixture();loadNative()
    local a=ZO_InventorySlotActions:New(false)
    local names={"AddMenuItem","AddCustomMenuItem","AddCustomSubMenuItem","AddCustomMenuTooltip","ShowMenu","ClearMenu"}
    for _,value in ipairs({"absent","false","function"}) do
        local original
        if value=="function" then original=function() end elseif value=="false" then original=false end
        for _,key in ipairs(names) do _G[key]=original end
        LibCustomMenu.AddMenuItem=original
        registryFixture(function() AddMenuItem("Action",function() end) end)
        b:_runContextCallbacks(LibCustomMenu,slot,a)
        for _,key in ipairs(names) do check(_G[key]==original,"nullable global not restored: "..key) end
        check(LibCustomMenu.AddMenuItem==original,"nullable LCM original not restored")
    end
    local marker=function() end
    for _,key in ipairs(names) do _G[key]=marker end
    local registry=registryFixture(function() end)
    registry.GetFireCallbackDepth=function() error("depth failed during setup") end
    local ok,err=pcall(function() b:_runContextCallbacks(LibCustomMenu,slot,a) end)
    check(not ok and tostring(err):find("depth failed during setup",1,true),"setup exception swallowed")
    check(not b._isCapturing and AddMenuItem==marker,"setup exception escaped cleanup")
    local hostile=setmetatable({CATEGORY_EARLY=1,CATEGORY_LATE=1,contextMenuRegistry=registry},{__newindex=function() error("partial setup failed") end})
    ok,err=pcall(function() b:_runContextCallbacks(hostile,slot,a) end)
    check(not ok and tostring(err):find("partial setup failed",1,true) and not b._isCapturing and AddMenuItem==marker,"partial replacement journal failed")
end)

test("live-registry",function()
    local b,s,slot=itemFixture();loadNative()
    local a=ZO_InventorySlotActions:New(false)
    local observed={}
    local registry=registryFixture(function() end)
    registry:ClearCallbackRegistry()
    local deleted=function() error("deleted callback dispatched") end
    registry:RegisterCallback(1,deleted,nil,20)
    registry:UnregisterCallback(1,deleted)
    local tail=function(argument,gotSlot,sa)
        check(argument=="arg" and gotSlot==slot and sa~=a,"native registry optional arg changed")
        observed[#observed+1]="tail"
    end
    registry:RegisterCallback(1,tail,"arg",30)
    registry:RegisterCallback(1,function()
        observed[#observed+1]="first"
        check(#b:_runContextCallbacks(LibCustomMenu,slot,a)==0,"reentrant dispatch was not blocked")
        registry:UnregisterCallback(1,tail,"arg")
    end,nil,10)
    b:_runContextCallbacks(LibCustomMenu,slot,a)
    check(table.concat(observed,",")=="first" and registry:GetFireCallbackDepth()==0,"live registry ordering/deletion ignored")
    registry:ClearCallbackRegistry();registry:RegisterCallback(1,tail,"arg")
    b:_runContextCallbacks(LibCustomMenu,slot,a)
    check(table.concat(observed,",")=="first,tail","registration changes hidden behind a registry cache")
end)

test("native-clear",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    local a=ZO_InventorySlotActions:New(false)
    a:SetInventorySlot(slot)
    ZO_CreateStringId("SI_BASE","Base")
    a:AddSlotAction(SI_BASE,function() end,"primary")
    registryFixture(function(_,sa)
        sa:Clear()
        check(sa:GetNumSlotActions()==0 and sa:GetAction(1)==nil and sa.m_inventorySlot==nil,"native Clear exposed inherited live state")
    end)
    local entries=b:_runContextCallbacks(LibCustomMenu,slot,a)
    check(a.m_inventorySlot==slot and #a.m_slotActions==1,"Clear leaked before commit")
    b:_appendEntriesToSlotActions(a,entries,slot)
    check(a.m_inventorySlot==nil and not a.m_hasActions and #a.m_slotActions==0,"native Clear state not committed coherently")
end)

test("native-death",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    local dead=false
    IsUnitDead=function() return dead end
    ZO_CreateStringId("SI_ALIVE","Alive");ZO_CreateStringId("SI_DEAD","Dead")
    local a=ZO_InventorySlotActions:New(false)
    registryFixture(function(_,sa)
        sa:AddSlotAction(SI_ALIVE,function() s.calls=s.calls+1 end,nil,nil,nil)
        sa:AddSlotAction(SI_DEAD,function() s.calls=s.calls+10 end,nil,nil,{visibleWhenDead=true})
    end)
    b:_appendEntriesToSlotActions(a,b:_runContextCallbacks(LibCustomMenu,slot,a),slot)
    dead=true;a.m_slotActions[1][2]();a.m_slotActions[2][2]()
    check(s.calls==10,"native alive/dead visibility/options policy lost")
end)

test("formatted-cache",function()
    local b,s,w=overlayFixture()
    for i=1,260 do
        b:_showOverlayLines({"Line "..i},"bag",control())
        local actual=0
        for _ in pairs(b._formattedTooltipLineCache) do actual=actual+1 end
        check(actual==b._formattedTooltipLineCacheSize and actual<=128,"formatted cache counter diverged after eviction")
    end
end)

test("no-fake-mouse-controls",function()
    local b=fresh()
    local c={entries={},contextControl={}}
    local evaluated=0
    b:_captureMenuEntry(c,function() evaluated=evaluated+1;error("mouse checkbox label evaluated") end,function() end,2,function() evaluated=evaluated+1 end)
    check(evaluated==0 and #c.entries==0,"unsupported top-level checkbox evaluated controls before rejection")
end)

test("unknown-result-link",function()
    local b=fresh()
    GetGameTimeMilliseconds=function() return 1000 end
    b._collectRecipeIngredients=function() return {{name="Mat",quantity=1,itemLink="|H1:item:1:|hMat|h"}} end
    b._getItemLinkQualityHex=function() return "FFFFFF" end
    b._getTtcPriceInfo=function() return {SuggestedPrice=1} end
    local lines=b:_buildCraftMaterialCostLines(nil,{recipeListIndex=1,recipeIndex=1})
    check(not contains(lines,"vs crafted:"),"unknown result link given market comparison")
end)

test("ttc-region",function()
    local b=fresh()
    local region,price,calls="EU",1,0
    TamrielTradeCentre={GetCurrentServerRegion=function() return region end}
    TamrielTradeCentrePrice={PriceTable={Data={},TimeStamp=1},GetPriceInfo=function() calls=calls+1;return {SuggestedPrice=price} end}
    local link="|H1:item:1:|hItem|h"
    b:_getCachedTtcTooltipLines(link)
    region,price="NA",2
    local lines=b:_getCachedTtcTooltipLines(link)
    check(calls==2 and contains(lines,"TTC: 2"),"TTC's region change ignored with same world/provider tables")
end)

test("registry-summary",function()
    local b,s,slot=itemFixture();loadNative()
    local registry=registryFixture(function() end)
    local priority=function() end
    local removed=function() end
    registry:RegisterCallback(1,priority,nil,10)
    registry:RegisterCallback(1,removed,nil,20)
    registry.fireCallbackDepth=1
    registry:UnregisterCallback(1,removed)
    local summary,total=b:_summarizeContextRegistry()
    check(total==2 and summary=="1:2","diagnostic count confused native priority and deleted indices")
end)

test("capture-identity",function()
    for _,initial in ipairs({"0","A"}) do
        local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
        s.id=initial
        local a=ZO_InventorySlotActions:New(false)
        registryFixture(function()
            AddMenuItem("Old identity",function() s.calls=s.calls+1 end)
            s.id="B"
        end)
        local entries=b:_runContextCallbacks(LibCustomMenu,slot,a)
        b:_appendEntriesToSlotActions(a,entries,slot)
        check(#a.m_slotActions==0,"capture was rebound to an identity that arrived during dispatch")
    end
end)

test("junk-unmark",function()
    for _,reason in ipairs({"valid","eligibility","locked","changed"}) do
        local b,s,slot=itemFixture();s.junk=true
        local a=b:_buildNativeJunkAction(slot)
        check(a~=nil,"eligible unmark action lost")
        if reason=="eligibility" then s.eligible=false elseif reason=="locked" then s.locked=true elseif reason=="changed" then s.junk=false end
        a.callback()
        check(s.calls==(reason=="valid" and 1 or 0),"unmark must revalidate current junk eligibility: "..reason)
    end
end)

test("native-context-policy",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    ZO_CreateStringId("SI_SHOWN","Shown");ZO_CreateStringId("SI_HIDDEN","Hidden");ZO_CreateStringId("SI_SILENT","Silent")
    local a=ZO_InventorySlotActions:New(false)
    local visibilityCalls=0
    registryFixture(function(_,sa)
        sa:AddSlotAction(SI_HIDDEN,function() error("hidden executed") end,nil,function() visibilityCalls=visibilityCalls+1;return nil end)
        sa:AddSlotAction(SI_SILENT,function() error("silent executed") end,nil,nil,"silent")
        sa:AddSlotAction(SI_SHOWN,function() end,"secondary",nil,{visibleWhenDead=true})
        check(sa:GetNumSlotActions()==3 and sa.m_numContextMenuActions==1,"native add/read/context-count semantics changed inside facade")
    end)
    b:_appendEntriesToSlotActions(a,b:_runContextCallbacks(LibCustomMenu,slot,a),slot)
    check(#a.m_slotActions==1 and a.m_slotActions[1][1]=="Shown","hidden/silent context rows leaked into gamepad menu")
    check(visibilityCalls==1,"native visibility evaluated again merely to merge")
    check(a.m_slotActions[1][3]=="secondary" and a.m_slotActions[1][5].visibleWhenDead,"visible native metadata stripped")
end)

test("material-setting",function()
    local b=fresh()
    b.savedVars={showTtcPriceInTooltip=false}
    local result="|H1:item:99:|hResult|h"
    local mat="|H1:item:98:|hMat|h"
    b._collectRecipeIngredients=function() return {{itemLink=mat,name="Mat",quantity=5}} end
    b._getItemLinkQualityHex=function() return "FFFFFF" end
    b._getTtcPriceInfo=function(_,link) return {SuggestedPrice=link==result and 100 or 10} end
    local lines=b:_buildCraftMaterialCostLines(result,{recipeListIndex=1,recipeIndex=1})
    check(contains(lines,"Mat total: 50") and contains(lines,"vs crafted: +50"),"unit-line preference unexpectedly disabled material estimates")
end)

test("native-cyclic-options",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    local a=ZO_InventorySlotActions:New(false)
    ZO_CreateStringId("SI_BASE","Base")
    local options={visibleWhenDead=true};options.self=options
    local calls=0
    a:AddSlotAction(SI_BASE,function() calls=calls+1 end,"primary",nil,options)
    registryFixture(function() end)
    b:_appendEntriesToSlotActions(a,b:_runContextCallbacks(LibCustomMenu,slot,a),slot)
    check(a.m_slotActions[1][5].self==a.m_slotActions[1][5],"native option cycles corrupted by capture")
    b.enabled=false;a.m_slotActions[1][2]()
    check(calls==1,"unchanged base native action was unnecessarily bridge-guarded")
end)

test("native-recreated-action",function()
    local b,s,slot=itemFixture();loadNative();b._buildNativeJunkAction=function() end
    ZO_CreateStringId("SI_BASE","Base")
    local callback=function() s.calls=s.calls+1 end
    local options={visibleWhenDead=true}
    local a=ZO_InventorySlotActions:New(false)
    a:AddSlotAction(SI_BASE,callback,"primary",nil,options)
    registryFixture(function(_,sa) sa:Clear();sa:AddSlotAction(SI_BASE,callback,"primary",nil,options) end)
    b:_appendEntriesToSlotActions(a,b:_runContextCallbacks(LibCustomMenu,slot,a),slot)
    s.id="B";a.m_slotActions[1][2]()
    check(s.calls==0,"new native row evaded item guard by matching old metadata")
end)

assert(not selected or groups == 1, "unknown contract group: " .. tostring(selected))
print("PASS " .. groups .. " contract groups")

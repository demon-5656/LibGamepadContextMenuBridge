# ESO Gamepad / TH Lua API — база знаний

Только факты, подтверждённые из исходников ESO.  
Ссылки для перепроверки — esoapi.uesp.net.

---

## Источники

| Файл | URL |
|------|-----|
| `tradinghouse_shared.lua` | https://esoapi.uesp.net/current/src/ingame/tradinghouse/tradinghouse_shared.lua |
| `tradinghouse_browseresults_gamepad.lua` | https://esoapi.uesp.net/current/src/ingame/tradinghouse/gamepad/tradinghouse_browseresults_gamepad.lua |
| `tradinghouse_templates_gamepad.lua` | https://esoapi.uesp.net/current/src/ingame/tradinghouse/gamepad/tradinghouse_templates_gamepad.lua |
| Корень tooltip-файлов | https://esoapi.uesp.net/current/src/ingame/tooltip/ |
| Браузер API (глобальные функции) | https://esoapi.uesp.net/current/src/libraries/ |

---

## TH данные — структура `selectedData`

Поля объекта, создаваемого `ZO_TradingHouse_CreateItemData`:

```lua
selectedData = {
    slotIndex          = index,       -- 1-based TH index (для GetTradingHouseSearchResultItemInfo)
    icon               = icon,
    name               = name,
    displayQuality     = displayQuality,
    quality            = displayQuality, -- deprecated alias
    stackCount         = stackCount,  -- количество в стопке
    sellerName         = sellerName,
    timeRemaining      = timeRemaining,
    purchasePrice      = purchasePrice,        -- ИТОГОВАЯ цена за всю стопку ← правильное имя
    purchasePricePerUnit = purchasePricePerUnit, -- цена за 1 штуку
    currencyType       = currencyType,
    itemLink           = itemLink,
    itemUniqueId       = itemUniqueId,
    isGuildSpecificItem = true,       -- только для гильдейских предметов
}
```

> **Ошибка-ловушка:** поле называется `purchasePrice`, не `totalPrice` и не `price`.

---

## TH API функции

```lua
-- Создание записи данных (используется при построении списка):
ZO_TradingHouse_CreateSearchResultItemData(index)  -- wrap над GetTradingHouseSearchResultItemInfo
ZO_TradingHouse_CreateListingItemData(index)       -- wrap над GetTradingHouseListingItemInfo

-- Нативные API (вызываются внутри Create*):
GetTradingHouseSearchResultItemInfo(index)
    -- → icon, name, displayQuality, stackCount, sellerName,
    --   timeRemaining, purchasePrice, currencyType, itemUniqueId, purchasePricePerUnit
GetTradingHouseSearchResultItemLink(index)  -- → itemLink

-- Количество результатов на текущей странице (не GetNumTradingHouseSearchResults!):
TRADING_HOUSE_SEARCH:GetNumItemsOnPage()
```

---

## Gamepad TH tooltip — поток вызовов

```
UpdateItemSelectedTooltip()  [ZO_GamepadTradingHouse_BrowseResults]
  └─ GAMEPAD_TOOLTIPS:LayoutGuildStoreSearchResult(
         GAMEPAD_RIGHT_TOOLTIP,
         itemLink,
         selectedData.stackCount,   ← stackCount всегда корректный
         selectedData.sellerName
     )
       └─ tooltip:LayoutItem(itemLink, ...)   ← вызывается внутри GSR
            └─ tooltip:ClearLines()
```

### Порядок хуков LGCMB

1. **LayoutItem pre-hook (call 1)** — срабатывает ДО вызова GSR (стейл-данные, pendingInfo не установлен). Ставит `pendingInfo = { link }` (без sc/price).
2. **ClearLines post-hook (после call 1)** — `pendingInfo` установлен с link-only → инжект TTC без цены/стопки.
3. **LayoutGuildStoreSearchResult pre-hook** — перезаписывает `pendingInfo = { link, stackCount, listingPrice }` (корректные данные).
4. **LayoutItem pre-hook (call 2, внутри GSR)** — `pendingInfo` уже установлен GSR → early return.
5. **ClearLines post-hook (после call 2)** — `pendingInfo` с корректными данными → финальный инжект TTC с ценой и стопкой.

---

## GAMEPAD_TOOLTIPS

```lua
GAMEPAD_TOOLTIPS:GetTooltip(tooltipType)  -- → tooltip object
-- Константы:
GAMEPAD_LEFT_TOOLTIP
GAMEPAD_RIGHT_TOOLTIP
GAMEPAD_MOVABLE_TOOLTIP

-- Методы tooltip-объекта:
tooltip:LayoutItem(itemLink, ...)
tooltip:LayoutBagItem(bagId, slotIndex, ...)
tooltip:LayoutGuildStoreSearchResult(itemLink, stackCount, sellerName, ...)  -- добавляется динамически при открытии TH
tooltip:LayoutFurnishingCraftingResult(...)
tooltip:ClearLines()
```

> `LayoutGuildStoreSearchResult` добавляется **динамически** при первом открытии TH.  
> `ZO_PreHook` тихо игнорирует вызов, если метод ещё не существует → нужен retry.

---

## GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS

```lua
-- Scroll list с результатами поиска:
local scene = GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS
local list = scene.itemList   -- ZO_GamepadInteractiveSortFilterList

-- Получить данные текущего выбранного элемента:
list:GetTargetData()   -- → selectedData (см. структуру выше)

-- Итерация scroll data (если нужен скан):
local scrollCtrl = list:GetScrollControl()   -- или list напрямую
-- scrollCtrl.data / scrollCtrl.scrollData — массив с .data[i] = selectedData
```

---

## ZO_PreHook / ZO_PostHook

```lua
-- Вставка до оригинала. Если pre-hook возвращает true — оригинал не вызывается.
ZO_PreHook(object, "MethodName", function(self, ...) end)

-- Вставка после оригинала.
ZO_PostHook(object, "MethodName", function(self, ...) end)

-- SecurePostHook — аналог ZO_PostHook, но через secure environment (для protected функций)
SecurePostHook(object, "MethodName", function(self, ...) end)
```

---

## Распространённые ошибки

| Ошибка | Правильно |
|--------|-----------|
| `selectedData.totalPrice` | `selectedData.purchasePrice` |
| `selectedData.price` | `selectedData.purchasePrice` |
| `selectedData.count` | `selectedData.stackCount` |
| `GetNumTradingHouseSearchResults()` | `TRADING_HOUSE_SEARCH:GetNumItemsOnPage()` |
| Хукать `LayoutItem` для TH-цены | Хукать `LayoutGuildStoreSearchResult` |

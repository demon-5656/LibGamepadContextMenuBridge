# Проверка контрактов ESO API 101051

Проверка исходников: 12 ноября 2026 года. Версия аддона: **1.5.4**.

## Источники

- ESO UI `live`, закреплённый commit `f819c808d57e237707c76e7b52518e2589c9e191`:
  https://github.com/esoui/esoui/tree/f819c808d57e237707c76e7b52518e2589c9e191
- Документация API: `ESOUIDocumentation.txt` в том же commit, заголовок **101051**.
- Оригинальные архивы ESOUI: LibCustomMenu **7.3.0 / 730**, LibAddonMenu-2.0 **2.0 r43**, Tamriel Trade Centre **4.27.281.39281**.
- Правила публикации: https://www.esoui.com/forums/showthread.php?t=9
- AI disclosure, credits и требования к зависимостям: https://www.esoui.com/forums/showthread.php?t=10790

Архивы и извлечённые текстовые источники использованы для чтения контрактов, а не как исполняемый игровой стенд. Рабочие материалы проверки находятся вне репозитория.

В официальном RSS `https://www.elderscrollsonline.com/en-us/rss/newspatcher` на момент проверки опубликованы live-заметки **Update 51 Incremental 2** (9 ноября 2026) и отдельно **PTS v12.2.2**. PTS не принимался за live-целевой API.

## Исправленные контракты

| Участок | Проверенный контракт и изменение |
|---|---|
| Время и строки | `GetTimeStamp()`, `GetString(...)`, `ZO_CreateStringId(...)` — штатные API; удалены проверки их существования, `pcall` и запасные способы вызова. |
| Меню LibCustomMenu | Используется `contextMenuRegistry:FireCallbacks(category, inventorySlot, slotActions)`. Категории — константы зависимости. Удалены повторный кэш регистраций и обход внутреннего реестра для повторного запуска. Пустое меню и ошибка не служат причиной повтора. |
| Ошибка строителя меню | В `ZO_CallbackObjectMixin:FireCallbacks` глубина увеличивается до внешнего callback. При исключении восстанавливается исходная глубина и выполняется `Clean(category)`; временно подменённые menu globals и context mode восстанавливаются отдельно. |
| Действия предмета | `ZO_InventorySlotActions:AddSlotAction` получает string ID; штатные поля `m_slotActions` хранят имя/функцию в индексах 1/2. Нет перебора выдуманных вариантов полей. |
| Типы списков | Parametric gamepad-списки используют `GetTargetData()`, но торговый BrowseResults наследует **ZO_SortFilterList:GetSelectedData()**. Применяется метод фактического класса, а не общий перебор имён; старые `SafeGetTargetData` и рекурсивные резолверы удалены за отсутствием оставшихся вызовов. |
| Рецепты | `GetRecipeInfo(list, recipe)` возвращает количество видов ингредиентов **третьим** значением. `GetRecipeIngredientRequiredQuantity(list, recipe, ingredient)` — необходимое количество. `GetCurrentRecipeIngredientCount` — запас у игрока, а не требуемое количество или число видов. |
| Поиск рецепта по результату | `GetRecipeInfoFromItemId(itemId)` возвращает тип станции и nullable-индексы рецепта. Убраны перебор всех рецептов и чтение произвольных вложенных UI-таблиц. |
| Smithing | Количество материала берётся из аргументов `ZO_GamepadSmithingCreation:SetupResultTooltip`, которые штатный UI передаёт в `LayoutPendingSmithingItem`, а не из другого tier, собственного запаса или значения по умолчанию `1`. Материал стиля и trait учитываются отдельно через `GetItemStyleMaterialLink` и `GetSmithingTraitItemLink`. |
| TTC | Используется `TamrielTradeCentrePrice:GetPriceInfo(itemLink)` и нормализованный объект, который возвращает TTC. Нет перебора альтернативных providers и способов вызова. Отсутствие TTC/его данных по-прежнему допустимо. |
| Торговый дом | Цена — `purchasePrice` текущего выбранного лота через `GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS:GetSelectedData()`. Проверяются точные itemLink, stackCount и sellerName; для guild-specific позиции ссылка получается по её собственному slotIndex, как в штатном `UpdateItemSelectedTooltip`. Нет поиска похожего item ID и возврата цены другого лота. |
| Gamepad crafting hooks | `ZO_GamepadSmithingCreation:SetupResultTooltip`, `ZO_GamepadProvisioner:RefreshRecipeDetails(selectedData)`, `ZO_GamepadAlchemy:UpdateTooltip` и `ZO_GamepadEnchanting:UpdateTooltip`. Используются реальные instance-owned `resultTooltip.tip` / `tooltip.tip`; не keyboard-классы, произвольные tooltip pools или несуществующий `LayoutFurnishingCraftingResult`. |
| Геометрия tooltip | `ZO_Tooltip:Initialize` примешивает методы к native control; `GAMEPAD_TOOLTIPS:GetTooltip` возвращает этот control. Используются его реальные методы геометрии и `IsControlHidden`, а не предположения о plain Lua object. |
| Зависимости | Required: `LibCustomMenu>=730`. Optional: `LibAddonMenu-2.0>=43`, `TamrielTradeCentre`. У TTC в проверенном manifest нет `AddOnVersion`, поэтому числовой минимум для него не выдуман. |

## Где обработка ошибок оправданна

Защита нужна на границе исполняемого кода стороннего аддона и при временной подмене menu globals. Она не проверяет наличие встроенной функции и не подбирает сигнатуру. Action callback вызывается один раз; строители меню не переигрываются после побочных эффектов. Проверки nil для ещё не созданных tooltip/UI instances и для необязательных аддонов — отдельные условия жизненного цикла, а не проверки наличия API.

## Пределы проверки

Manifest обновлён на **101051** по исходникам, а не только по номеру в комментарии. Старые API targets не заявляются как поддержанные без проверки.

Локальные Lua-тесты используют явно заданные ESO/TTC fixtures и проверяют управление вызовами, материалы, выбранный лот и таймеры. Они не доказывают игровую совместимость, внешний вид, отсутствие taint или работу с каждым сторонним аддоном.

На итоговом коде пройдены `luac5.1 -p`, **10 групп / 131 проверка** из `scripts/tests/regression.lua` и `git diff --check`. Все **32 прямых вызова глобальных API** найдены в закреплённой документации или глобальных Lua-определениях; это лексическая проверка существования, не доказательство семантики всех методов. Проверены CRC, состав и побайтовое совпадение кода в ZIP 1.5.3 с проверенным исходником. В продуктовом файле осталось **3 `pcall` вместо 67** — только указанные выше границы стороннего кода и очистки capture.

Смета smithing использует обычный материал выбранного стиля; замена его на Crown Mimic Stone отдельно не моделируется. Сравнение рыночной цены результата с материалами не является расчётом чистой прибыли.

Первоначальный пользовательский прогон 1.5.3 был отмечен успешным, но затем Azmail прислал фактическую ошибку инициализации: `SecurePostHook: table expected, got userdata`. Это выявило пробел в прежних табличных fixtures.

## Хотфикс 1.5.4

Native tooltip — `userdata` с Lua-методами. Его геометрические методы корректны, но `SecurePostHook` принимает в объектной форме только таблицу. Для `LayoutBagItem` и `LayoutGuildStoreSearchResult` применён `ZO_PostHook`: штатная реализация в `esoui/libraries/utility/zo_hook.lua` читает и присваивает метод через индекс объекта, что подходит native control. Хуки Lua-классов остаются `SecurePostHook`.

Regression fixtures теперь используют настоящий Lua `userdata`, а `SecurePostHook` отвергает его точно как клиент. До исправления воспроизведена та же ошибка на строке 1656; после замены обеих регистраций пройдены 10 групп / 140 проверок, включая однократность вызова и сохранение return value штатного layout. Beta-статус сохранён. Подробные игровые сценарии находятся в [приёмке выпуска](ACCEPTANCE_AND_RELEASE.md).

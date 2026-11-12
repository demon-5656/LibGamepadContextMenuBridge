# Контракты ESO API 101051

**1.5.5 — development; игровая приёмка NOT RUN.** Ниже описаны контракты первоисточников, реализованные исправления и локальные проверки. Локальный PASS не является проверкой в ESO.

## Источники и границы

Проверка пяти reviews от 12 ноября 2026 года использовала ESO UI `live`, commit `f819c808d57e237707c76e7b52518e2589c9e191`; заголовок `ESOUIDocumentation.txt` — **101051**. PTS 101052 не заявляется как проверенная совместимость.

Первичные тексты зависимостей прочитаны в локальной установке: LibCustomMenu **7.3.0 / AddOnVersion 730**, LibAddonMenu-2.0 **2.0 r43**, TTC **4.27.281.39281**. Это проверенные тексты, не утверждение о свежем скачивании архивов или последних опубликованных версиях. Полные отчёты и probes хранятся вне Git.

Точные файлы native source ниже относятся к этому SHA. Их корень: `esoui/` в репозитории `esoui/esoui` на GitHub. C++ VM здесь не исполнялась; экспортированный API и Lua call sites не доказывают поведение всех overloads.

## Меню и выполнение действий

| Область | Подтверждённый контракт / граница adapter |
|---|---|
| Registry | `LibCustomMenu:RegisterContextMenu(callback, category, ...)` регистрирует callback в живом registry. Сборка через `contextMenuRegistry:FireCallbacks(category, inventorySlot, slotActions)`. `callback/arg/priority/deleted` — поля CallbackObject, не произвольные varargs. Пустой результат не повод повторять сборку. |
| Native rebuild | `ingame/inventory/itemslotactioncontroller.lua:108–120` вызывает discovery, затем `RefreshKeybindStrip` в одном `RebuildActions`. Два независимых post-hooks не должны запускать builders дважды. Проверяется также пустой builder. |
| Slot actions | `ingame/inventory/inventoryslotactions.lua:167–203`: `AddSlotAction` сразу читает `GetString(id)`, обновляет action/keybind tables и счётчики. `GetNumSlotActions` / `GetSlotAction` должны видеть согласованное состояние. Для capture нужен изолированный coherent facade, а не только перехват `AddMenuItem`. Сохранять action type, visibility, options, silent/visibleWhenDead и read/adjust semantics. |
| Capture | Подготовка, replacement и registry-depth lookup должны находиться внутри защищённой transaction. Journal восстанавливает точные originals, включая nil, при частичной ошибке setup и builder. Не оставлять live actions после неудачной сборки. Capture не продолжается через таймеры. |
| Обычное действие | Поддерживаемый label callback вызывается без аргументов, один раз на принятую активацию. Исключение не разрешает повтор с другой сигнатурой. Ошибка может возникнуть после side effect, который bridge не умеет откатить. |
| Submenu checkbox | LCM `Submenu` вызывает child callback с новым boolean-состоянием. Сохраняется плоская строка `Parent: Child`; выбор ребёнка не вызывает parent. |
| Mouse controls | Native top-level checkbox вызывает `(buttonControl, checked)`, parent LCM — `(control)`, entries-builder — `(ZO_Menu, control)`, label/checked/disabled evaluators — `(ZO_Menu, submenuItem)`. Inventory row не является этим control. Genuine parent/top-level checkbox и control-dependent формы пропускаются с диагностикой, без fake controls. |
| Visibility | LCM задаёт default true только отсутствующему `visible`; явно заданная функция получает `ZO_Menu`, её nil/false скрывает строку. Проверять truthiness отдельно от отсутствия поля. |
| Item identity | Bag/slot — адрес, itemLink — вариант, ни то ни другое не уникальный экземпляр. Перед native junk и injected side effects нужно заново проверить unique ID, enabled/mode и допустимость операции. Смена экземпляра, в том числе при одинаковом link, отменяет старое действие. |

Источники LCM: `LibCustomMenu.lua:259,308–311,434–497,723–790,862–865`. Native checkbox: `libraries/zo_contextmenus/zo_contextmenus.lua:266–289`, `libraries/zo_templates/buttontemplates.lua:260–280`. Registry: `libraries/utility/zo_callbackobject.lua:23–62,109–195`. Это контрактные ориентиры, не стабильные номера строк production bridge.

## Tooltip, выбор и lifecycle

- `ZO_Tooltip` — native userdata с Lua mixins. `ZO_PostHook` подходит для его layout-методов; table-форма `SecurePostHook(targetTable, name, callback)` подтверждена exported API. Native классы остаются Lua tables.
- Строгий table-only mock **не доказывает отсутствие string/global-name overload** `SecurePostHook`: такие вызовы есть в реальных установленных аддонах. Предыдущая ошибка userdata подтверждена, но это другое утверждение.
- `libraries/zo_tooltip/zo_tooltip.lua:61–67,439–440,1205–1207`: mixed-in `GetParent()` возвращает styled parent, у root это nil, не native ancestry. Геометрию брать у явного owner/container, не у прокручиваемого content tip.
- `common/zo_tooltip/gamepad/zo_tooltip_gamepad.lua:312–321`: `GetTooltip(type)` возвращает content, `GetTooltipContainer(type)` — внешний контейнер. Crafting owner — `creation.resultTooltip`, `provisioner.resultTooltip`, `alchemy.tooltip` или `enchanting.resultTooltip`; `.tip` — содержимое.
- Hidden owner не заменяется любым другим видимым tooltip. Hide/selection/source/scene/mode/disable инвалидируют запрос; retry сохраняет исходный token. После исчерпания попыток без anchor окно остаётся скрытым.
- BrowseResults class local; экспортирован `GAMEPAD_TRADING_HOUSE_BROWSE_RESULTS`. Его `GetSelectedData()` наследуется от `ZO_SortFilterList`. Использовать точный selectedData/index/generation, поля `itemLink`, `stackCount`, `sellerName`, `purchasePrice`; guild-specific link читается по собственному slotIndex. Не применять `itemList:GetTargetData()` и поиск похожего item ID.
- `LayoutBagItem(bagId, slotIndex, showCombinedCount, extraData)` и `LayoutGuildStoreSearchResult(itemLink, stackCount, sellerName, timeRemainingText)` подтверждены в `publicallingames/tooltip/itemtooltips.lua:1882,2342–2356`.
- Crafting hooks: `ZO_GamepadSmithingCreation:SetupResultTooltip`, `ZO_GamepadProvisioner:RefreshRecipeDetails(selectedData)`, `ZO_GamepadAlchemy:UpdateTooltip`, `ZO_GamepadEnchanting:UpdateTooltip`. `LayoutFurnishingCraftingResult` не является подтверждённым методом.

## Цены и материалы

| Область | Контракт |
|---|---|
| Item link | `GetLinkType(string)` возвращает enum `LinkType`; сравнение с `LINK_TYPE_ITEM`. `ITEM_LINK_TYPE = "item"` — строковый link-handler token, не enum. Nil/type boundary не доказывает существование предмета. |
| TTC | Только публичный `TamrielTradeCentrePrice:GetPriceInfo(itemLink)` с self; table или nil, нормализованные `SuggestedPrice/Avg/Min/Max`. Отсутствие provider/PriceTable/цены допустимо. Raw compressed fields не являются API bridge. |
| Cache | Generation учитывает provider, region, PriceTable, Data и TimeStamp; положительные и отрицательные результаты имеют ограниченный TTL. Retained displayed model наследует ближайший expiry. Обновляется только ещё актуальный видимый owner, без скрытого polling. Unit/stack/comparison должны использовать согласованный price snapshot. |
| Recipe inputs | `GetRecipeInfo(list, recipe)` result #3 — число видов ингредиентов; `GetRecipeIngredientRequiredQuantity` — требуемое количество, не owned stock. `GetRecipeInfoFromItemId` возвращает station и nullable recipe indices. |
| Recipe output | `GetRecipeResultQuantity(list, recipe, numIterations)` даёт выход. Native `ingame/crafting/sharedprovisioner.lua:278–280` применяет его для числа результатов. Полную стоимость одного craft нельзя сравнивать с ценой одной штуки при output > 1. Неизвестный выход не подменять единицей для достоверной delta. |
| Smithing | Аргументы `SetupResultTooltip(pattern, materialIndex, materialQuantity, styleId, traitIndex)` соответствуют native `LayoutPendingSmithingItem`. Брать выбранную materialQuantity; style/trait отдельно через `GetItemStyleMaterialLink` / `GetSmithingTraitItemLink` (trait index, не enum). Crown Mimic Stone отдельно не моделируется. |
| Неполнота | Суммировать весь состав, а не только восемь видимых строк. Недоступные состав/цены отмечать; сравнение не является чистой прибылью и не включает автоматически все сборы/специальные правила. |

## Зависимости, строки и настройки

- Required `LibCustomMenu>=730`: порог по integer `AddOnVersion`, не отображаемому `Version`. Это поддерживаемая нижняя граница, не утверждение о первой версии появления каждого метода.
- Optional `LibAddonMenu-2.0 TamrielTradeCentre`: порядок загрузки, не обязательность; version comparison для optional не действует. `PCDependsOn` / `ConsoleDependsOn` — platform-specific required, не optional. Console support не заявляется.
- `ZO_SavedVars:NewAccountWide(..., defaults, GetWorldName())`: world — пятый аргумент profile (`libraries/utility/zo_savedvars.lua:67–69`). EU/NA-профили наследуют legacy только при отсутствии собственного; false и независимую копию log сохранять, старые данные не удалять.
- UI hooks откладываются до readiness/gamepad, повторные установки не размножаются. Disable/mode/interaction close отменяют соответствующие listeners/updaters; включение внутри открытой станции/TH требует актуального close listener.
- `SafeAddString` позволяет обновлять один private StringId; native `AddSlotAction` snapshot-ит текст синхронно. Это не обещание совместимости со сторонней заменой метода, откладывающей чтение ID.
- Штатные helpers: `zo_strtrim`, `GetItemQualityColor(...):ToHex()`, `ZO_CombineNumericallyIndexedTables`, `zo_strformat(SI_TOOLTIP_ITEM_NAME, name)`. Копирование не должно менять исходные cached arrays.

## История локальных проверок, не финальная оценка

| Этап | Записанный тогда результат |
|---|---|
| 1.5.3 | 10 групп / 131 assertion; лексическая сверка 32 global API; CRC/состав/byte compare тогдашнего ZIP |
| 1.5.4 userdata correction | 10 групп / 140 проверок; до фикса воспроизведена ошибка userdata |
| Ранняя 1.5.5 | 13 групп / 230 assertions; с реальным pinned SavedVars — 13 / 226 (разница — четыре fixture assertions) |
| Повторный refactor 1.5.5 | 15 групп / 264 assertions; тогдашний ZIP из четырёх файлов проверен; Lua 2446 → 2342 строки относительно `2add83a` |
| Перед пятью reviews | 18 групп / 809 assertions; 3000 подписей / 1 выделенный StringId |
| База пяти reviews `77ed20e` + dirty TTC fix | 18 групп / 815 assertions под Lua 5.1 и обычным Lua; дополнительные probes выявили реальные пробелы этих fixtures |

Эти числа — история разных состояний, **815 не является финальным результатом текущего исправления**. Новый итог берётся только из реально исполненного финального harness с указанием состояния кода. Восемь quality probes PASS означали успешное воспроизведение дефектов, не их исправление. Старый четырёхфайловый ZIP не подтверждает нынешнюю корректность лицензии/упаковки.

Первоначальный успешный отчёт Azmail о 1.5.3 позднее дополнился фактической startup-ошибкой `SecurePostHook: table expected, got userdata`. Он не переносится на 1.5.5. Lua fixtures не доказывают secure/taint, engine geometry, protected side effects, визуальную совместимость или измеренное ускорение.

## Текущая локальная проверка

Реализованы и проверены unique identity/actions, один context builder dispatch, capture setup/rollback и coherent slotActions, unsupported-control filtering, visible nil, owner/container/retry exhaustion, TTC generation/TTL и recipe output basis. Дополнительные integration-сценарии загружают реальный LCM HookContextMenu и native tooltip manager: keybind lifecycle, смешанный ClearMenu/sa:Clear, смена layout без hide и nullable unique ID.

Независимый повтор под Lua 5.1 и Lua 5.5: **18 regression groups / 849 assertions + 25 contract groups + 4 integration groups**, syntax и diff checks — PASS. Полный запуск требует `ESO_NATIVE_SOURCE` (pinned ESO checkout) и `ESO_LCM_SOURCE` (исходник LibCustomMenu 7.3.0); точные команды — в [приёмке](ACCEPTANCE_AND_RELEASE.md).

Независимо повторены **14 PASS** в `python3 -B scripts/tests/test_packaging.py` на disposable synthetic repos. Прочитанный новый `build_release.py` использует Python 3 stdlib, allowlist manifest/Lua/README/CREDITS + root LICENSE внутри addon folder, проверяет версии/runtime filenames, CRC и байты, запрещает overwrite, включая concurrent build. `build_release.sh` — совместимый wrapper; executable `zip` не требуется. Это не игровые тесты; реальный dist/release в текущей задаче не собирался.

После локальных проверок остаются [игровые acceptance gates](ACCEPTANCE_AND_RELEASE.md). До их выполнения 1.5.5 остаётся development/test; публикационные тексты — черновики для решения владельца. Упаковка и разрешение на публикацию проверяются отдельно.

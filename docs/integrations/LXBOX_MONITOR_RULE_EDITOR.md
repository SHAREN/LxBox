# L×Box Monitor 0.6.0 — безопасное редактирование правил без новой APK LBox

**Реализовано в отдельном приложении** [L×Box Monitor 0.6.0](https://github.com/SHAREN/lxbox-routing/releases/tag/lxbox-monitor-v0.6.0). В самом LBox ни изменений, ни пересборки не требуется: используются существующие локальные Debug API endpoint'ы.

## Что работает

Monitor → Маршруты → Удобный редактор LBox → вставить URL → **«Открывать этот сайт через VPN»** → подтвердить предпросмотр → применить.

Это строго ограниченный редактор: меняет **только** список `domain_suffixes` у пользовательского правила `RU MOBILE · local blocked domains → VPN` с `outbound=vpn-1`. Показывает добавленные домены, позволяет удалить домен через подтверждение или отменить последнее изменение.

Прочие правила, включая `RU MOBILE · whitelist domains → DIRECT`, `Gemini web Chrome → Gemini Auto`, Tailscale и любые настройки VPN-серверов, не меняются. Существующие правила доступны для поиска и просмотра; широкое редактирование будет реализовано отдельно.

## API-интеграция

1. **GET /rules** → найти правило по точному имени, проверить enabled/kind/outbound и порядок относительно двух direct-правил. Приоритеты на Pixel 7 Pro: override 947, direct apps 948, whitelist direct 949.
2. При вводе URL — выделить ASCII/IDNA домен без пути или параметров. Отклонить локальные IP, приватные домены, опасные широкие зоны.
3. **Preview (локально)** → одноразовый nonce, текущий и будущий размер списка, предупреждение о перезапуске маршрутов. Само правило пока не меняется.
4. **POST/PATCH /rules/{id}?rebuild=true** с телом исключительно `{"domain_suffixes":[...]}`. До записи сверить сохранённую копию с актуальным списком: если правило редактировали извне, не перезаписывать.
5. **POST /action/check-config** → проверить новый конфиг самим ядром LBox. При неуспехе восстановить прежний список.
6. **POST /action/reload-vpn** → in-place reload. Если соединение с локальным API прервалось после попытки reload, вернуть пользователю неопределённость и сохранить резервную точку, не выполнять второй reload вслепую.
7. **Undo** → восстановить старый список только если текущее правило точно совпадает с последним применённым.

## Безопасность

- Сам Monitor хранит Bearer токен Debug API через Android Keystore. Токен никогда не отдаётся JavaScript.
- Никакого общего прокси по произвольным API путям; только специализированная Java-обёртка для этого правила.
- В процессе работы никаких автоматических изменений при открытии приложения, чтении состояния или обновлении карточек.
- Изменения выполняются только по отдельному подтверждению и могут на несколько секунд прервать VPN-трафик.
- Не изменяются NORMAL/WHITELIST, Tailscale, исключения Android-приложений, выбора VPN-узлов и маршруты ChatGPT/Gemini/Telegram.
- В v0.6.0 нет общего редактора Raw JSON конфигурации: он намеренно не открыт через JavascriptInterface, чтобы не сломать рабочий VPN.

## Source / verification

- [Java bridge LBoxRuleEditor.java](https://github.com/SHAREN/lxbox-routing/blob/main/apps/lxbox-companion/app/src/main/java/ru/sharen/lxboxcompanion/LBoxRuleEditor.java)
- [UI L×Box Monitor](https://github.com/SHAREN/lxbox-routing/blob/main/apps/lxbox-companion/app/src/main/assets/index.html)
- [Подробная спецификация](https://github.com/SHAREN/lxbox-routing/blob/main/apps/lxbox-companion/docs/LBOX_RULE_EDITOR_V06.md)
- [UI tests](https://github.com/SHAREN/lxbox-routing/blob/main/apps/lxbox-companion/tools/test-domain-editor-ui.js)

**Проверено:** APK Monitor 0.6.0 успешно собрана и запущена на эмуляторе, JS тесты пройдены, установлена поверх существующей Monitor на Pixel 7 Pro (versionCode 8). На Pixel после установки подтверждено, что LBox connected, NORMAL и исходные приоритеты правил не изменились. **Живые PATCH/reload в рабочем LBox не запускались**, пока пользователь сам не выберет сайт и не нажмёт «Применить».

## Следующая стадия

Удобное редактирование других типов правил (выбор направления VPN/DIRECT, per-app правила, поиск/фильтры, DNS, список исключений, экспорт/импорт) с отдельными жёсткими контрактами, preview, проверкой и rollback. Нельзя подключать веб-панель как unrestricted конфигурационный proxy.

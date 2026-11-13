# LBox ↔ L×Box Monitor: подтверждённый тест Gemini API

**Подтверждено на Pixel 7 Pro 2026-11-13 09:09 (UTC+05)** в отдельных Google Gemini API-проверках через LBox Monitor 0.5.1, с одним сохранённым API-ключом и без генерации текста.

| VPN-outbound (`gemini-auto`) | Ответ `models.list?pageSize=1` | Вердикт Monitor |
|---|---|---|
| `✨ One-(Первый)✨` | HTTP **400**, явный региональный отказ | `region_blocked_api` |
| `✨ AI🤖` | HTTP **200**, получены модели | `api_available` |

Не путать с `✨ Германия🇩🇪`: у этого узла ранее воспроизводилась веб-заглушка, но *авторизованный API-key тест с HTTP 400 в этой паре был проведён на One-(Первый)*.

## Схема взаимодействия

```text
L×Box Monitor (ru.sharen.lxboxcompanion)
  ├─ Android Keystore: Gemini API key (AES-GCM, локально)
  ├─ localhost LBox Debug API (127.0.0.1:9269)
  │   ├─ GET /state/route-status  → выбранный gemini-auto узел
  │   ├─ GET /rules               → правило Gemini API → gemini-auto
  │   └─ GET /settings/tun_apps   → приложение не исключено из VPN
  └─ Android VPN Network.openConnection (fail-closed)
       → sing-box LBox route: generativelanguage.googleapis.com → gemini-auto
       → HTTPS GET /v1beta/models?pageSize=1
          x-goog-api-key: [только в запросе к Google]
       ← HTTP status + классификация API, дата, имя узла
```

**Свойства:** не поднимать второй VPN, не перезагружать LBox, не менять NORMAL/WHITELIST/Tailscale, не выдавать ключ Google в Debug API или GitHub. `models.list` не генерирует текст и не расходует inference-токены. Квоты и цены Google могут изменяться.

Положительный `200` **подтверждает Gemini API**, не обязательно веб-чат пользователя. `400` региональный — только при явном Google-маркере неподдерживаемой страны. API-key валидатор исправлен в Monitor v0.5.1: сохранение проверяется чтением из Android Keystore, поле больше не стирается при ошибке.

**Техническое доказательство, чек-лист регрессий и ссылки:**
[SHAREN/lxbox-routing — A/B Gemini API, 2026-11-13](https://github.com/SHAREN/lxbox-routing/blob/main/docs/verification/GEMINI_API_AB_2026-11-13.md).

**Код Monitor:** [SHAREN/lxbox-routing/apps/lxbox-companion](https://github.com/SHAREN/lxbox-routing/tree/main/apps/lxbox-companion).  
**Код специальных возможностей LBox Debug API:** [PR #4 — live-маршруты, пинг и проверка Gemini](https://github.com/SHAREN/LxBox/pull/4) (черновик; базу и регрессии ещё требуется согласовать).  
**Дальнейшая работа:** [issue #5 — достоверная проверка доступности Gemini на каждом VPN-узле](https://github.com/SHAREN/LxBox/issues/5).

**Ограничение:** автоматического переключения и массового сканирования всех узлов нет. Наблюдения подтверждают только два конкретных выбранных узла и состояние на дату проверки.

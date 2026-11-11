# Task — read-only route status for external L×Box monitor

## Scenario

Companion APK on Pixel 7 Pro must show the actually selected physical node for each
`chatgpt-auto`, `gemini-auto`, and `telegram-auto` direction, the last core
URLTest ping in milliseconds, and the exact elapsed time since that measurement.
Currently `GET /state` exposes `selected_group` and `active_in_group` only
for the foreground direction; a separate companion cannot infer other selectors.
Do not invent selected nodes or ping ages from saved config or request time.

## Change

Enrich authenticated, read-only `GET /state` with:

For true live selection while the LBox UI is backgrounded, also add `GET /state/route-status` using a 2-second bounded CommandClient `getGroups()` snapshot. A 200 response labels `source=kernel_unary` only after successful kernel fetch; on failure it returns the cached Home snapshot labelled `source=cached_home` (not claimed live). The companion reads this endpoint when available and degrades safely on older LBox versions.
- `route_groups[]` from the live CommandClient `HomeState.ccGroups`:
  `tag,type,selected,selectable,items[{tag,type,delay_ms,checked_at_unix_s}]`.
- `service_health` snapshot of session-only, explicitly initiated
  NET / YT / GPT / GEM service checks; HTTP status and elapsed duration only.

The source of `checked_at_unix_s` is the core `CcOutbound.urlTestTime`;
zero denotes never tested. This is not the same as the timestamp of the current
HTTP API read. No new probes are initiated when reading the endpoint.

## Boundaries and acceptance

- No proxy URIs, passwords, bearer tokens, subscription URLs or test bodies.
- Endpoint remains behind the existing Debug API Bearer token on localhost.
- Each individual selector exports its **actual live** choice, not its configured
  default. Nested urltest selectors can be resolved by consumers.
- A failed/untested/stale core ping is not called service availability; service
  specific checks remain separately labeled.
- No changes to VPN routing, `tun_apps`, Tailscale or switching logic.
- Validate serializer tests, release build; deliver patched LBox APK only if
  signing/update compatibility is known. Never silently replace live VPN.

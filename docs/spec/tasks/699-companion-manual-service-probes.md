# Task 699 — on-demand checks from standalone L×Box Monitor

## Why

The user wants manual Ping and Service/Region check buttons for each
ChatGPT, Gemini and Telegram route in the separate Android Monitor. The
monitor must NOT create a VPN/proxy test session; network probes must run
through the physical outbound currently selected by the running L×Box
CommandClient. The companion only starts a test and reads its result.

## Protocol

Authenticated Debug API on loopback port 9269:

- POST /action/monitor-probe?direction=chatgpt-auto&kind=ping
- POST /action/monitor-probe?direction=gemini-auto&kind=service
- POST /action/monitor-probe?direction=telegram-auto&kind=service
- GET /state/monitor-probes

Only three known direction tags and kinds ping|service accepted.
The server uses a fresh getGroups() and follows selected selector/urltest
members, including nested groups. If an individual selector is omitted from
the returned kernel groups but the VPN is up, it tests through the fixed
logical direction outbound tag (e.g., telegram-auto) and explicitly reports
selection_source=logical_direction; it does not falsely name a physical node.
Callers cannot pass a raw node tag or URL.
The POST returns accepted and selected_tag; the check executes asynchronously.
GET returns per-direction/per-kind state and exact completed timestamp.

Ping: CommandClient.urlTestOutbound over the selected tag; standard
Cloudflare generate_204 URL, 5 s budget. 0 ms is a valid success, failures
are not a "green" 0-ms result.

Service test: CommandClient.getUrlViaOutbound using a fixed endpoint:
ChatGPT API /v1/models, Gemini /app, Telegram web /a/.
Returns state available/blocked/indeterminate/failed, response HTTP code,
elapsed time, selected outbound and completed_at timestamp. ChatGPT region
blocking requires the explicit unsupported-country marker (generic 403 is
ambiguous). Gemini anonymous 200 verifies transport only, not signed-in
account/region access; its diagnostic helper can fall back to URLTest but
MUST stay indeterminate. Telegram HTTPS reachability does not prove chat login.
No credentials, body text, or arbitrary native error message exported.

## UX

Two compact buttons per service card, with independent progress and
last-result blocks; completed_at shown as seconds/minutes ago.
If a route changed since measurement, say explicitly "tested another server".
A positive ping only verifies outbound URLTest, NOT service availability.
Running an action is always explicit; polling never starts a probe.
Keep NORMAL/WHITELIST and Tailscale untouched.

## Safety

- Debug API already enforces loopback + Bearer.
- Java bridge hardcodes the three directions and two kinds, POST localhost only.
- Bearer stays in Android Keystore, never JS, git, URLs, screenshots or logs.
- No repeated automatic requests; duplicate starts rejected; 4-second cooldown.
- Old tests are labeled with time, and no claim is made after >15 min.
- Results session-only on LBox, without persistent tracking of internet use.
- Explicit endpoint calls do not modify selector state.

## Acceptance

- Mocked CommandClient API test calls urlTestOutbound and HTTP via selected
  live outbound, asserts timing and blocked classification.
- Unknown direction and duplicate actions safely rejected.
- NodeJS DOM simulation tests buttons, renderings, stale and region labels.
- Build both APKs, verify signatures against prior local artifacts.
- No direct installation that could disrupt the active VPN without explicit
  consent; deliver manual update artifacts and test instructions.
